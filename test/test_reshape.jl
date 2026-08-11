using TimeSeries

@testset "reshape" begin
    ipi = read_sdmx_csv(joinpath(@__DIR__, "fixtures", "istat_ipi_2026-08.csv"))

    @testset "to_wide: one column per varying-dimension combination" begin
        wide = to_wide(ipi)
        @test names(wide)[1] == "period"
        # only ECON_ACTIVITY_NACE_2007 varies in the fixture → bare codes as names
        @test "0020" in names(wide)
        @test ncol(wide) == 1 + length(unique(ipi.ECON_ACTIVITY_NACE_2007))
        @test issorted(wide.period)
        i = findfirst(==(Date(2026, 6, 1)), wide.period)
        @test wide[i, "0020"] == 93.5

        # a single constant series gets its full key as the column name
        one = ipi[ipi.ECON_ACTIVITY_NACE_2007 .== "0020", :]
        w1 = to_wide(one)
        @test names(w1) == ["period", "M.IT.IND_PROD_21.Y.0020"]

        # explicit `by`
        w2 = to_wide(ipi; by = ["ECON_ACTIVITY_NACE_2007"])
        @test names(w2) == names(wide)
        @test_throws ArgumentError to_wide(ipi; by = ["NOPE"])
    end

    @testset "mixed frequencies error, never silently misalign" begin
        mixed = read_sdmx_csv("""
        DATAFLOW,FREQ,TIME_PERIOD,OBS_VALUE
        IT1:X(1.0),M,2026-01,1.0
        IT1:X(1.0),Q,2026-Q1,2.0
        """)
        @test_throws ArgumentError to_wide(mixed)
        @test_throws ArgumentError to_timearray(mixed)
    end

    @testset "to_timearray via the TimeSeries extension" begin
        ta = to_timearray(ipi[ipi.ECON_ACTIVITY_NACE_2007 .∈ Ref(["0020", "0040"]), :])
        @test ta isa TimeArray
        @test length(colnames(ta)) == 2
        @test timestamp(ta)[1] isa Date
        @test values(ta[Date(2026, 6, 1)][Symbol("0020")])[1] == 93.5
    end

    @testset "the stub errors helpfully without TimeSeries" begin
        # the extension is loaded here, so exercise the stub directly
        err = try
            invoke(to_timearray, Tuple{Any}, 42)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("using TimeSeries", err.msg)
    end
end
