@testset "dataflows" begin
    IPI_DIMS = ["FREQ", "REF_AREA", "DATA_TYPE", "ADJUSTMENT", "ECON_ACTIVITY_NACE_2007"]

    @testset "shipped snapshot serves everything with zero requests" begin
        log = String[]
        with_transport(recording_transport(Dict{String,Any}(); log)) do
            df = get_dataflows()
            @test nrow(df) > 4000
            @test names(df) == ["id", "agency", "version", "name_en", "name_it",
                                "dsd", "dsd_version", "last_update", "metadata_url"]
            @test eltype(df.id) == String          # never missing, never pooled surprises

            row = get_dataflow("115_333")
            @test row.name_en == "Industrial production index"
            @test row.dsd == "DCSC_INDXPRODIND_1"
            # all three spellings round-trip to the same flow
            @test get_dataflow("IT1,115_333,1.0").id == "115_333"
            @test get_dataflow("IT1:115_333(1.0)").id == "115_333"
            @test_throws ArgumentError get_dataflow("999_999_nope")

            # dimension count pinned at 5: a spurious sixth key position is a
            # silent wrong-answer bug
            dims = get_dimensions("115_333")
            @test dims == IPI_DIMS
            @test length(dims) == 5

            # flow-based key construction, validated against the DSD
            @test sdmx_key("115_333"; FREQ = "M", ADJUSTMENT = "Y") == "M...Y."
            @test_throws ArgumentError sdmx_key("115_333"; FRQE = "M")
        end
        @test isempty(log)
    end

    @testset "second structure lookup makes zero extra loads" begin
        # the in-memory catalogue cache: no file re-read, no transport
        log = String[]
        with_transport(recording_transport(Dict{String,Any}(); log)) do
            @test get_dimensions("115_333") == IPI_DIMS
            @test get_dimensions("115_333") == IPI_DIMS
        end
        @test isempty(log)
    end

    @testset "JSON parsers against captured fixture slices" begin
        body = read(joinpath(@__DIR__, "fixtures", "dataflows_IT1_slice.json"), String)
        df = IstatApi._parse_dataflows_json(body)
        @test issorted(df.id)
        i = findfirst(==("115_333"), df.id)
        @test i !== nothing
        @test df.name_it[i] == "Indice della produzione industriale"
        @test df.dsd[i] == "DCSC_INDXPRODIND_1"
        @test df.dsd_version[i] == "1.0"
        @test occursin(r"^\d{4}-\d{2}-\d{2}T", df.last_update[i])

        body = read(joinpath(@__DIR__, "fixtures", "datastructures_IT1_slice.json"), String)
        ds = IstatApi._parse_datastructures_json(body)
        sub = ds[ds.dsd .== "DCSC_INDXPRODIND_1", :]
        @test sub.dimension == IPI_DIMS
        @test sub.position == 1:5
        @test sub.codelist == ["CL_FREQ", "CL_ITTER107", "CL_TIPO_DATO7",
                               "CL_CORREZ", "CL_ATECO_2007"]
        # the TimeDimension is not a key position
        @test !("TIME_PERIOD" in ds.dimension)
    end

    @testset "refresh = true fetches once, then shadows the snapshot" begin
        url = string(IstatApi.ENDPOINT[], "/dataflow/IT1")
        body = read(joinpath(@__DIR__, "fixtures", "dataflows_IT1_slice.json"), String)
        log = String[]
        try
            with_online() do
                with_transport(recording_transport(Dict(url => (200, [], body)); log)) do
                    with_fast_limit() do
                        df = get_dataflows(refresh = true)
                        @test nrow(df) == 63
                        @test log == [url]
                        # the refreshed copy now shadows the shipped snapshot,
                        # still zero further requests
                        @test nrow(get_dataflows()) == 63
                        @test log == [url]
                        @test isfile(joinpath(cache_dir(), "dataflows_IT1.csv"))
                        @test isfile(joinpath(cache_dir(), "dataflows_IT1.csv.meta.toml"))
                    end
                end
            end
        finally
            reset_catalogue!()
        end
        @test nrow(get_dataflows()) > 4000     # shipped snapshot again
    end

    @testset "unknown agency points at refresh" begin
        @test_throws ArgumentError get_dataflows(agency = "ESTAT")
    end
end
