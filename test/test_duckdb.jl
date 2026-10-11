using DuckDB

@testset "duckdb" begin
    ipi = read_sdmx_csv(joinpath(@__DIR__, "fixtures", "istat_ipi_2026-08.csv"))
    q(con, sql) = DataFrame(DuckDB.execute(con, sql))

    @testset "default table name from DATAFLOW" begin
        @test IstatApi._duckdb_table_name(ipi) == "istat_115_333"
        two = vcat(ipi[1:1, :], ipi[1:1, :]; cols = :union)
        two.DATAFLOW[2] = "IT1:999_1(1.0)"
        @test_throws ArgumentError IstatApi._duckdb_table_name(two)
        @test_throws ArgumentError IstatApi._duckdb_table_name(DataFrame(a = [1]))
    end

    @testset "round trip keeps codes as strings, missing as NULL" begin
        con = DuckDB.DB()
        @test to_duckdb(con, ipi) == "istat_115_333"
        # stored as period_freq (FREQ and freq collide in SQL)…
        @test "period_freq" in names(q(con, "SELECT * FROM istat_115_333"))
        # …and read_duckdb restores the get_data schema
        back = read_duckdb(con, "istat_115_333")
        @test names(back) == names(ipi)
        @test nrow(back) == nrow(ipi)
        @test eltype(back.ECON_ACTIVITY_NACE_2007) <: Union{Missing,String}
        @test "0020" in back.ECON_ACTIVITY_NACE_2007
        @test eltype(back.period) <: Union{Missing,Date}
        @test count(ismissing, back.OBS_VALUE) == count(ismissing, ipi.OBS_VALUE)
        # a read-back result reshapes exactly like the original
        @test to_wide(back) == to_wide(ipi)
        close(con)
    end

    @testset "upsert replaces revised observations, never duplicates" begin
        con = DuckDB.DB()
        to_duckdb(con, ipi)
        revised = copy(ipi)
        revised.OBS_VALUE = coalesce.(revised.OBS_VALUE, 0.0) .+ 1
        to_duckdb(con, revised)
        @test q(con, "SELECT count(*) AS n FROM istat_115_333").n[1] == nrow(ipi)
        @test q(con, "SELECT count(*) AS n FROM istat_115_333 WHERE OBS_VALUE IS NULL").n[1] == 0

        # :append duplicates on purpose; :replace starts over
        to_duckdb(con, ipi; mode = :append)
        @test q(con, "SELECT count(*) AS n FROM istat_115_333").n[1] == 2nrow(ipi)
        to_duckdb(con, ipi; mode = :replace)
        @test q(con, "SELECT count(*) AS n FROM istat_115_333").n[1] == nrow(ipi)
        close(con)
    end

    @testset "schema drift: new label columns are added" begin
        con = DuckDB.DB()
        to_duckdb(con, ipi; table = "ipi")
        labelled = copy(ipi)
        insertcols!(labelled, findfirst(==("FREQ"), names(ipi)) + 1,
                    :FREQ_label => fill("Monthly", nrow(ipi)))
        to_duckdb(con, labelled; table = "ipi")
        back = read_duckdb(con, "ipi")
        @test "FREQ_label" in names(back)
        @test nrow(back) == nrow(ipi)
        @test all(==("Monthly"), back.FREQ_label)
        close(con)
    end

    @testset "argument errors" begin
        con = DuckDB.DB()
        @test_throws ArgumentError to_duckdb(con, ipi; mode = :merge)
        @test_throws ArgumentError to_duckdb(con, DataFrame(code = ["0020"]); table = "cl")
        @test to_duckdb(con, DataFrame(code = ["0020"]); table = "cl", mode = :replace) == "cl"
        @test read_duckdb(con, "SELECT code FROM cl").code == ["0020"]
        # other case-insensitive collisions are refused up front
        @test_throws ArgumentError to_duckdb(con, DataFrame(a = [1], A = [2]);
                                             table = "bad", mode = :replace)
        # upserting one flow into a table holding another flow's schema
        to_duckdb(con, DataFrame(DATAFLOW = ["IT1:X(1.0)"], TIME_PERIOD = ["2026"],
                                 OBS_VALUE = [1.0]); table = "other")
        @test_throws ArgumentError to_duckdb(con, ipi; table = "other")
        # the failed upsert rolled back: no columns added, no rows touched
        @test names(q(con, "SELECT * FROM other")) == ["DATAFLOW", "TIME_PERIOD", "OBS_VALUE"]
        close(con)
    end

    @testset "catalogue tables, zero requests" begin
        con = DuckDB.DB()
        before = requests_used()
        @test catalogue_to_duckdb(con) == ["istat_dataflows", "istat_dimensions"]
        @test requests_used() == before
        @test q(con, "SELECT count(*) AS n FROM istat_dataflows").n[1] == nrow(get_dataflows())
        dims = q(con, """
            SELECT d.dimension FROM istat_dataflows f
            JOIN istat_dimensions d ON d.dsd = f.dsd AND d.version = f.dsd_version
            WHERE f.id = '115_333' ORDER BY d.position""")
        @test dims.dimension == get_dimensions("115_333")
        close(con)
    end

    @testset "stubs error helpfully without DuckDB" begin
        err = try
            invoke(read_duckdb, Tuple{Any,Any}, 1, 2)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("using DuckDB", err.msg)
        @test_throws ErrorException invoke(to_duckdb, Tuple{Any,Any}, 1, 2)
    end
end
