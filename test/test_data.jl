@testset "data" begin
    IPI_CSV = read(joinpath(@__DIR__, "fixtures", "istat_ipi_2026-08.csv"), String)
    LABELS_CSV = read(joinpath(@__DIR__, "fixtures", "istat_ipi_labels_2026.csv"), String)
    CHILDREN = read(joinpath(@__DIR__, "fixtures", "dsd_115_333_children_trimmed.json"), String)
    AVAIL_XML = read(joinpath(@__DIR__, "fixtures", "availableconstraint_115_333.xml"), String)

    CHILDREN_URL = string(IstatApi.ENDPOINT[],
        "/datastructure/IT1/DCSC_INDXPRODIND_1/1.0?references=children")
    IPI_URL = sdmx_url("115_333", "M.IT.IND_PROD_21.Y.")

    @testset "get_data end to end: exact URL, parse, cache" begin
        log = String[]
        with_online() do
            with_transport(recording_transport(Dict(IPI_URL => (200, [], IPI_CSV)); log)) do
                with_fast_limit() do
                    df = get_data("115_333"; FREQ = "M", REF_AREA = "IT",
                                  DATA_TYPE = "IND_PROD_21", ADJUSTMENT = "Y")
                    @test log == [IPI_URL]
                    @test nrow(df) == 3180
                    @test df.ECON_ACTIVITY_NACE_2007 isa Vector{String}
                    @test "0020" in df.ECON_ACTIVITY_NACE_2007
                    @test eltype(df.OBS_VALUE) == Union{Float64,Missing}

                    # the plan's verification numbers: −0.95% m/m in June 2026
                    sub = df[(df.ECON_ACTIVITY_NACE_2007 .== "0020"), :]
                    may = sub.OBS_VALUE[findfirst(==("2026-05"), sub.TIME_PERIOD)]
                    jun = sub.OBS_VALUE[findfirst(==("2026-06"), sub.TIME_PERIOD)]
                    @test may == 94.4
                    @test jun == 93.5

                    # second call: cache hit, zero transport calls
                    df2 = get_data("115_333"; FREQ = "M", REF_AREA = "IT",
                                   DATA_TYPE = "IND_PROD_21", ADJUSTMENT = "Y")
                    @test log == [IPI_URL]
                    @test df2.OBS_VALUE == df.OBS_VALUE

                    # a typo'd dimension dies before the network
                    @test_throws ArgumentError get_data("115_333"; FRQE = "M")
                    @test log == [IPI_URL]
                end
            end
        end
        clear_cache!()
    end

    @testset "from/to land in the URL as startPeriod/endPeriod" begin
        url = sdmx_url("115_333", "M.IT.IND_PROD_21.Y.0020"; from = "2020", to = "2024-12")
        log = String[]
        with_online() do
            with_transport(recording_transport(Dict(url => (200, [], IPI_CSV)); log)) do
                with_fast_limit() do
                    get_data("115_333"; FREQ = "M", REF_AREA = "IT",
                             DATA_TYPE = "IND_PROD_21", ADJUSTMENT = "Y",
                             ECON_ACTIVITY_NACE_2007 = "0020",
                             from = "2020", to = "2024-12", cache = false)
                    @test log == [url]
                end
            end
        end
    end

    @testset "labels = true joins locally from the cached codelists" begin
        log = String[]
        try
            with_online() do
                with_transport(recording_transport(Dict(
                        IPI_URL => (200, [], IPI_CSV),
                        CHILDREN_URL => (200, [], CHILDREN)); log)) do
                    with_fast_limit() do
                        df = get_data("115_333"; FREQ = "M", REF_AREA = "IT",
                                      DATA_TYPE = "IND_PROD_21", ADJUSTMENT = "Y",
                                      labels = true)
                        # exactly two requests: the data and the DSD — labels are free
                        @test sort(log) == sort([IPI_URL, CHILDREN_URL])
                        @test "ADJUSTMENT_label" in names(df)
                        i = findfirst(==("Y"), df.ADJUSTMENT)
                        @test df.ADJUSTMENT_label[i] == "seasonally adjusted data"
                        j = findfirst(==("0020"), df.ECON_ACTIVITY_NACE_2007)
                        @test occursin("TOTAL INDUSTRY", df.ECON_ACTIVITY_NACE_2007_label[j])
                        # label columns sit right after their code column
                        k = findfirst(==("ADJUSTMENT"), names(df))
                        @test names(df)[k+1] == "ADJUSTMENT_label"
                    end
                end
            end
        finally
            empty!(IstatApi._DSD_CACHE)
            clear_cache!()
        end
    end

    @testset "labels = :server parses the relabelled headers" begin
        url = sdmx_url("115_333", "M.IT.IND_PROD_21.Y.0020"; from = "2026-01")
        log = String[]
        with_online() do
            with_transport(recording_transport(Dict(url => (200, [], LABELS_CSV)); log)) do
                with_fast_limit() do
                    df = get_data("115_333", "M.IT.IND_PROD_21.Y.0020";
                                  from = "2026-01", labels = :server, cache = false)
                    @test log == [url]
                    @test "period" in names(df) && "freq" in names(df)
                    @test df.period[1] == Date(2026, 1, 1)
                    @test df.OBS_VALUE[1] == 93.5
                    # "CODE: label" headers and cells are split back into the
                    # plain schema plus <DIM>_label columns — same shape as
                    # labels = true, so reshapers work on either
                    @test df.FREQ == fill("M", nrow(df))
                    @test df.FREQ_label == fill("monthly", nrow(df))
                    @test df.ECON_ACTIVITY_NACE_2007[1] == "0020"
                    @test occursin("TOTAL INDUSTRY", df.ECON_ACTIVITY_NACE_2007_label[1])
                    @test names(df)[1:3] == ["DATAFLOW", "FREQ", "FREQ_label"]
                    @test !("TIME_PERIOD_label" in names(df))     # no labelled cells
                    wide = to_wide(df)
                    @test names(wide) == ["period", "M.IT.IND_PROD_21.Y.0020"]
                    @test wide[1, 2] == 93.5
                end
            end
        end
        @test_throws ArgumentError get_data("115_333", "."; labels = :banana)
    end

    @testset "last_n / first_n reach the URL and skip the size guard" begin
        url = sdmx_url("115_333", sdmx_key("115_333"); last_n = 12)
        log = String[]
        with_online() do
            with_transport(recording_transport(Dict(url => (200, [], IPI_CSV)); log)) do
                with_fast_limit() do
                    # a fully wildcarded key, but bounded → no nobs request first
                    df = get_data("115_333"; last_n = 12, cache = false)
                    @test log == [url]
                    @test nrow(df) == 3180
                end
            end
        end
    end

    @testset "trim = true drops observations after `to` (endPeriod over-returns)" begin
        url = sdmx_url("115_333", "M.IT.IND_PROD_21.Y.0020"; to = "2026-03")
        url_q = sdmx_url("115_333", "M.IT.IND_PROD_21.Y.0020"; to = "2026-Q1")
        log = String[]
        with_online() do
            # the fixture runs to 2026-06, standing in for the server's extra year
            with_transport(recording_transport(Dict(url => (200, [], IPI_CSV),
                                                    url_q => (200, [], IPI_CSV)); log)) do
                with_fast_limit() do
                    df = get_data("115_333", "M.IT.IND_PROD_21.Y.0020";
                                  to = "2026-03", cache = false)
                    @test log == [url]
                    @test maximum(df.period) == Date(2026, 3, 1)
                    @test nrow(df) < 3180
                    raw = get_data("115_333", "M.IT.IND_PROD_21.Y.0020";
                                   to = "2026-03", trim = false, cache = false)
                    @test maximum(raw.period) == Date(2026, 6, 1)
                    # a quarterly bound keeps the whole quarter
                    q = get_data("115_333", "M.IT.IND_PROD_21.Y.0020";
                                 to = "2026-Q1", trim = true, cache = false)
                    @test maximum(q.period) == Date(2026, 3, 1)
                end
            end
        end
    end

    @testset "fully wildcarded queries are sized first and refused" begin
        wildkey = sdmx_key("115_333")
        nobs_url = string(IstatApi.ENDPOINT[],
            "/availableconstraint/115_333/", wildkey, "/all/FREQ")
        wild_url = sdmx_url("115_333", wildkey)
        log = String[]
        with_online() do
            with_transport(recording_transport(Dict(
                    nobs_url => (200, [], AVAIL_XML),
                    wild_url => (200, [], IPI_CSV)); log)) do
                with_fast_limit() do
                    # 187,956 > max_obs → refused after the 3 KB sizing request
                    @test_throws ArgumentError get_data("115_333")
                    @test log == [nobs_url]
                    # the ready-made-key form is guarded too (sizing is cached)
                    @test_throws ArgumentError get_data("115_333", wildkey)
                    @test log == [nobs_url]
                    @test nobs("115_333", wildkey) == 187_956
                    @test nobs("115_333") == 187_956
                    @test log == [nobs_url]
                    # explicit override fetches
                    df = get_data("115_333"; max_obs = nothing, cache = false)
                    @test log == [nobs_url, wild_url]
                    @test nrow(df) == 3180
                end
            end
        end
    end

    @testset "industrial_production shortcut = documented get_data call" begin
        url = sdmx_url("115_333", "M.IT.IND_PROD_21.Y.0020+0040")
        log = String[]
        with_online() do
            with_transport(recording_transport(Dict(url => (200, [], IPI_CSV)); log)) do
                with_fast_limit() do
                    df = industrial_production(codes = ["0020", "0040"])
                    @test log == [url]
                    @test nrow(df) > 0
                end
            end
        end
        clear_cache!()
    end
end
