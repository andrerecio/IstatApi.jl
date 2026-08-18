@testset "structure" begin
    CHILDREN_URL = string(IstatApi.ENDPOINT[],
        "/datastructure/IT1/DCSC_INDXPRODIND_1/1.0?references=children")
    children_body = read(joinpath(@__DIR__, "fixtures",
                                  "dsd_115_333_children_trimmed.json"), String)
    avail_xml = read(joinpath(@__DIR__, "fixtures",
                              "availableconstraint_115_333.xml"), String)

    @testset "get_datastructure: one request, then memoised" begin
        log = String[]
        try
            with_online() do
                with_transport(recording_transport(Dict(CHILDREN_URL => (200, [], children_body)); log)) do
                    with_fast_limit() do
                        ds = get_datastructure("115_333")
                        @test log == [CHILDREN_URL]
                        @test ds.id == "DCSC_INDXPRODIND_1"
                        @test ds.version == "1.0"
                        @test ds.dimensions == ["FREQ", "REF_AREA", "DATA_TYPE",
                                                "ADJUSTMENT", "ECON_ACTIVITY_NACE_2007"]
                        @test ds.codelist_of["FREQ"] == "CL_FREQ"
                        @test ds.codelist_of["ECON_ACTIVITY_NACE_2007"] == "CL_ATECO_2007"

                        corr = ds.codelists["CL_CORREZ"]
                        @test nrow(corr) == 4
                        i = findfirst(==("N"), corr.code)
                        @test corr.name_en[i] == "raw data"
                        @test corr.name_it[i] == "dati grezzi"

                        # hierarchical codelists carry the parent
                        ateco = ds.codelists["CL_ATECO_2007"]
                        j = findfirst(==("01"), ateco.code)
                        @test j !== nothing && ateco.parent[j] == "A"

                        # the show method prints the key template
                        shown = sprint(show, MIME("text/plain"), ds)
                        @test occursin("FREQ.REF_AREA.DATA_TYPE.ADJUSTMENT.ECON_ACTIVITY_NACE_2007", shown)
                        @test occursin("CL_ATECO_2007", shown)
                        @test !occursin("large", shown)   # trimmed fixture, no big codelist

                        # a huge codelist gets a hint pointing at `available`
                        big = DataStructure("IT1", "BIG", "1.0", ["FREQ", "TERR"],
                                            Dict("TERR" => "CL_TERR"),
                                            Dict("CL_TERR" => DataFrame(
                                                code = string.(1:1200), name_en = fill("", 1200),
                                                name_it = fill("", 1200), parent = fill("", 1200))),
                                            String["OBS_STATUS"])
                        bigshown = sprint(show, MIME("text/plain"), big)
                        @test occursin("CL_TERR (1200 codes) — large; available(flow, \"TERR\")", bigshown)
                        @test occursin("key template: FREQ.TERR", bigshown)
                        @test occursin("attributes: OBS_STATUS", bigshown)

                        # second call: zero transport calls (memoised)
                        ds2 = get_datastructure("115_333")
                        @test ds2 === ds
                        @test log == [CHILDREN_URL]
                    end
                end
            end
        finally
            empty!(IstatApi._DSD_CACHE)
        end
        @test isempty(IstatApi._DSD_CACHE)
    end

    @testset "get_codelist languages and warnings" begin
        log = String[]
        try
            with_online() do
                with_transport(recording_transport(Dict(CHILDREN_URL => (200, [], children_body)); log)) do
                    with_fast_limit() do
                        cl = get_codelist("115_333", "ADJUSTMENT")
                        @test names(cl) == ["code", "name_en", "name_it", "parent"]
                        @test nrow(cl) == 4
                        @test names(get_codelist("115_333", "ADJUSTMENT"; lang = :en)) ==
                              ["code", "name_en", "parent"]
                        @test names(get_codelist("115_333", "ADJUSTMENT"; lang = :it)) ==
                              ["code", "name_it", "parent"]
                        @test_throws ArgumentError get_codelist("115_333", "NOPE")
                        @test_throws ArgumentError get_codelist("115_333", "FREQ"; lang = :de)
                        # zero transport calls: the children response cached
                        # on disk by the previous testset serves everything —
                        # cross-session caching working as designed
                        @test isempty(log)
                    end
                end
            end
        finally
            empty!(IstatApi._DSD_CACHE)
        end
    end

    @testset "_parse_available extracts obs_count and codes" begin
        obs, kvs = IstatApi._parse_available(avail_xml)
        @test obs == 187956
        codes = kvs["ECON_ACTIVITY_NACE_2007"]
        @test "0020" in codes
        @test "0040" in codes
        @test length(codes) > 100          # far more than a test stub, far less than 2,063
        @test allunique(codes)
    end

    @testset "available and nobs build the verified URL shape" begin
        avail_url = string(IstatApi.ENDPOINT[],
            "/availableconstraint/115_333/M...Y./all/ECON_ACTIVITY_NACE_2007")
        nobs_url = string(IstatApi.ENDPOINT[],
            "/availableconstraint/115_333/M...Y./all/FREQ")
        responses = Dict(avail_url => (200, [], avail_xml),
                         nobs_url => (200, [], avail_xml))
        log = String[]
        with_online() do
            with_transport(recording_transport(responses; log)) do
                with_fast_limit() do
                    av = available("115_333", "ECON_ACTIVITY_NACE_2007";
                                   FREQ = "M", ADJUSTMENT = "Y")
                    @test log == [avail_url]           # exact URL, exactly one request
                    @test names(av) == ["code"]
                    @test "0020" in av.code

                    n = nobs("115_333"; FREQ = "M", ADJUSTMENT = "Y")
                    @test n == 187956
                    @test log == [avail_url, nobs_url]

                    # a typo'd dimension dies before the network
                    @test_throws ArgumentError available("115_333", "ECON";
                                                         FREQ = "M")
                    @test_throws ArgumentError nobs("115_333"; FRQE = "M")
                    @test length(log) == 2
                end
            end
        end
    end

    @testset "offline blocks structure fetches but not snapshot lookups" begin
        empty!(IstatApi._DSD_CACHE)
        clear_cache!()          # the fixture responses were cached above
        @test isoffline()
        @test_throws OfflineError get_datastructure("115_333")
        @test get_dimensions("115_333") isa Vector{String}   # snapshot: still fine
    end

    @testset "nobs without an obs_count annotation is a RequestFailed, not a guess" begin
        url = string(IstatApi.ENDPOINT[], "/availableconstraint/115_333/..../all/FREQ")
        no_count = "<structure:ContentConstraint></structure:ContentConstraint>"
        with_online() do
            with_transport(recording_transport(Dict(url => (200, [], no_count)))) do
                with_fast_limit() do
                    @test_throws RequestFailed nobs("115_333")
                end
            end
        end
        clear_cache!()
    end

    @testset "refresh = true on structures: one live request each, then shadowing" begin
        cat_url = string(IstatApi.ENDPOINT[], "/datastructure/IT1")
        cat_body = read(joinpath(@__DIR__, "fixtures", "datastructures_IT1_slice.json"), String)
        log = String[]
        try
            with_online() do
                with_transport(recording_transport(Dict(
                        cat_url => (200, [], cat_body),
                        CHILDREN_URL => (200, [], children_body)); log)) do
                    with_fast_limit() do
                        dims = get_dimensions("115_333"; refresh = true)
                        @test dims == ["FREQ", "REF_AREA", "DATA_TYPE", "ADJUSTMENT",
                                       "ECON_ACTIVITY_NACE_2007"]
                        @test log == [cat_url]
                        @test isfile(joinpath(cache_dir(), "datastructures_IT1.csv"))
                        # the refreshed copy is served afterwards, zero requests
                        get_dimensions("115_333")
                        @test log == [cat_url]

                        # get_datastructure(refresh = true) bypasses memo and cache
                        ds1 = get_datastructure("115_333")
                        @test log == [cat_url, CHILDREN_URL]
                        ds2 = get_datastructure("115_333"; refresh = true)
                        @test log == [cat_url, CHILDREN_URL, CHILDREN_URL]
                        @test ds2.dimensions == ds1.dimensions
                        @test get_datastructure("115_333") === ds2   # re-memoised
                        @test length(log) == 3
                    end
                end
            end
        finally
            reset_catalogue!()
            empty!(IstatApi._DSD_CACHE)
            clear_cache!()
        end
    end
end
