@testset "keys" begin
    # The IPI DSD's five dimensions, pinned: a spurious sixth position in a key
    # is a silent wrong-answer bug, so the count is part of the contract.
    IPI = ["FREQ", "REF_AREA", "DATA_TYPE", "ADJUSTMENT", "ECON_ACTIVITY_NACE_2007"]

    @testset "order, wildcards, +-joins" begin
        @test sdmx_key(IPI) == "...."
        @test count(==('.'), sdmx_key(IPI)) == length(IPI) - 1
        @test sdmx_key(IPI; FREQ = "M") == "M...."
        @test sdmx_key(IPI; ECON_ACTIVITY_NACE_2007 = "C") == "....C"
        @test sdmx_key(IPI; FREQ = "M", ADJUSTMENT = "Y",
                       ECON_ACTIVITY_NACE_2007 = ["0020", "0040", "C"]) ==
              "M...Y.0020+0040+C"
        # kwarg order is irrelevant; DSD order rules
        @test sdmx_key(IPI; ADJUSTMENT = "Y", FREQ = "M") ==
              sdmx_key(IPI; FREQ = "M", ADJUSTMENT = "Y")
        # tuples work like vectors; Symbols are fine as codes
        @test sdmx_key(IPI; DATA_TYPE = ("ISAV", "ESAV")) == "..ISAV+ESAV.."
        @test sdmx_key(IPI; FREQ = :M) == "M...."
    end

    @testset "typos and footguns die locally, not on the wire" begin
        @test_throws ArgumentError sdmx_key(IPI; FRQE = "M")
        @test_throws ArgumentError sdmx_key(IPI; freq = "M")
        # numbers would corrupt zero-padded codes
        @test_throws ArgumentError sdmx_key(IPI; ECON_ACTIVITY_NACE_2007 = 20)
        @test_throws ArgumentError sdmx_key(IPI; ECON_ACTIVITY_NACE_2007 = ["0020", 40])
        # codes that would break key syntax
        @test_throws ArgumentError sdmx_key(IPI; FREQ = "M.Q")
        @test_throws ArgumentError sdmx_key(IPI; FREQ = "A+B")
        @test_throws ArgumentError sdmx_key(IPI; FREQ = "")
        @test_throws ArgumentError sdmx_key(IPI; FREQ = String[])
        @test_throws ArgumentError sdmx_key(String[])
    end

    @testset "flowRef spellings normalise and round-trip" begin
        @test IstatApi._flow_ref("115_333") == "IT1,115_333"
        @test IstatApi._flow_ref("115_333"; agency = "IT2") == "IT2,115_333"
        @test IstatApi._flow_ref("IT1,115_333,1.0") == "IT1,115_333,1.0"
        # the DATAFLOW column's form
        @test IstatApi._flow_ref("IT1:115_333(1.0)") == "IT1,115_333,1.0"
    end

    @testset "sdmx_url" begin
        @test sdmx_url("115_333", "M...Y.") ==
              "https://esploradati.istat.it/SDMXWS/rest/data/IT1,115_333/M...Y."
        @test sdmx_url("115_333", "M...Y.", from = "2020", to = "2024-12") ==
              "https://esploradati.istat.it/SDMXWS/rest/data/IT1,115_333/M...Y.?startPeriod=2020&endPeriod=2024-12"
        @test sdmx_url("IT1:115_333(1.0)", ".....", from = 2020) ==
              "https://esploradati.istat.it/SDMXWS/rest/data/IT1,115_333,1.0/.....?startPeriod=2020"
        # lastNObservations / firstNObservations, after the period bounds
        @test sdmx_url("115_333", "M...Y.", last_n = 12) ==
              "https://esploradati.istat.it/SDMXWS/rest/data/IT1,115_333/M...Y.?lastNObservations=12"
        @test sdmx_url("115_333", "M...Y.", from = "2020", first_n = 3) ==
              "https://esploradati.istat.it/SDMXWS/rest/data/IT1,115_333/M...Y.?startPeriod=2020&firstNObservations=3"
        @test_throws ArgumentError sdmx_url("115_333", "M...Y.", last_n = 0)
        @test_throws ArgumentError sdmx_url("115_333", "M...Y.", first_n = -1)
        # wildcard detection drives the size guard in get_data
        @test IstatApi._is_fully_wildcarded("....")
        @test IstatApi._is_fully_wildcarded(".")
        @test !IstatApi._is_fully_wildcarded("M...Y.")
        @test !IstatApi._is_fully_wildcarded("M.IT")
        # a swapped endpoint flows through
        IstatApi.set_endpoint!("https://example.invalid/rest")
        try
            @test startswith(sdmx_url("X", "."), "https://example.invalid/rest/data/IT1,X/.")
        finally
            IstatApi.set_endpoint!("https://esploradati.istat.it/SDMXWS/rest")
        end
    end
end
