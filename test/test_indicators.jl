@testset "indicators" begin
    IPI_CSV = read(joinpath(@__DIR__, "fixtures", "istat_ipi_2026-08.csv"), String)

    @testset "_edition_key orders ISTAT vintages correctly" begin
        k = IstatApi._edition_key
        @test k("2026M10") > k("2026M7")        # lexicographic would get this wrong
        @test k("2026M7G30") > k("2026M7G2")
        @test k("2024M10_1") > k("2024M10")
        @test k("2025M1") > k("2024M12")
        @test k("garbage") == (0, 0, 0, 0)      # unparseable sorts first
        @test maximum(k, ["2025M10", "2026M3", "2026M1_1", "junk"]) == k("2026M3")
    end

    @testset "edition = :latest resolves via one availableconstraint request" begin
        avail_xml = """
        <structure:ContentConstraint>
          <common:Annotation id="obs_count"><common:AnnotationTitle>123</common:AnnotationTitle></common:Annotation>
          <common:KeyValue id="EDITION">
            <common:Value>2025M10</common:Value>
            <common:Value>2026M1_1</common:Value>
            <common:Value>2026M3</common:Value>
          </common:KeyValue>
        </structure:ContentConstraint>
        """
        gdpkey_noedition = "Q.IT.B1GQ_B_W2_S1.L_2020.Y."
        avail_url = string(IstatApi.ENDPOINT[],
            "/availableconstraint/163_156/", gdpkey_noedition, "/all/EDITION")
        data_url = sdmx_url("163_156", "Q.IT.B1GQ_B_W2_S1.L_2020.Y.2026M3")
        log = String[]
        with_online() do
            with_transport(recording_transport(Dict(
                    avail_url => (200, [], avail_xml),
                    data_url => (200, [], IPI_CSV)); log)) do
                with_fast_limit() do
                    gdp(cache = false)
                    @test log == [avail_url, data_url]
                end
            end
        end
    end

    @testset "pinned editions skip the resolution request" begin
        cases = [
            (() -> gdp(edition = "2026M5", cache = false),
             sdmx_url("163_156", "Q.IT.B1GQ_B_W2_S1.L_2020.Y.2026M5")),
            (() -> unemployment(edition = "2026M7G30", cache = false),
             sdmx_url("151_874", "M.IT.UNEM_R.Y.9.Y15-74.2026M7G30")),
            (() -> consumer_prices(cache = false),
             sdmx_url("167_745", "M.IT.85.4.00")),
            (() -> consumer_prices(measure = "7", coicop = "01", cache = false),
             sdmx_url("167_745", "M.IT.85.7.01")),
        ]
        for (call, url) in cases
            log = String[]
            with_online() do
                with_transport(recording_transport(Dict(url => (200, [], IPI_CSV)); log)) do
                    with_fast_limit() do
                        call()
                        @test log == [url]    # exactly one request, exact URL
                    end
                end
            end
        end
    end
end
