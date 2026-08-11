using Sockets

@testset "transport" begin
    @testset "offline mode blocks uncached fetches, before the transport" begin
        log = String[]
        with_transport(recording_transport(Dict{String,Any}(); log)) do
            @test isoffline()
            @test_throws OfflineError IstatApi._fetch("https://example.invalid/nope")
        end
        @test isempty(log)
    end

    @testset "status handling and caching" begin
        url200 = "https://example.invalid/data/ok"
        responses = Dict(
            url200 => (200, [], "DATAFLOW,FREQ\nx,y\n"),
            "https://example.invalid/404" => (404, [], ""),
            "https://example.invalid/204" => (204, [], ""),
            "https://example.invalid/empty" => (200, [], ""),
            "https://example.invalid/500" => (500, [], "boom"),
        )
        log = String[]
        with_online() do
            with_transport(recording_transport(responses; log)) do
                with_fast_limit() do
                    body = IstatApi._fetch(url200; accept = "text/csv")
                    @test body == "DATAFLOW,FREQ\nx,y\n"
                    @test log == [url200]

                    # cache hit: same body, zero transport calls
                    @test IstatApi._fetch(url200; accept = "text/csv") == body
                    @test log == [url200]

                    # a different Accept is a different entry
                    IstatApi._fetch(url200; accept = "application/json")
                    @test length(log) == 2

                    # force bypasses the cache
                    IstatApi._fetch(url200; accept = "text/csv", force = true)
                    @test length(log) == 3

                    @test_throws NoDataError IstatApi._fetch("https://example.invalid/404")
                    @test_throws NoDataError IstatApi._fetch("https://example.invalid/204")
                    @test_throws NoDataError IstatApi._fetch("https://example.invalid/empty")
                    @test_throws RequestFailed IstatApi._fetch("https://example.invalid/500")
                end
            end
        end
        @test url200 in cache_index().url
        # ...and the cached copy still serves with the fixture gone and the
        # package offline — the property the whole design exists for.
        @test IstatApi._fetch(url200; accept = "text/csv") == "DATAFLOW,FREQ\nx,y\n"
        clear_cache!()
    end

    @testset "429 writes the ban sentinel; the sentinel blocks pre-network" begin
        url429 = "https://example.invalid/limited"
        responses = Dict(
            url429 => (429, ["Retry-After" => "60"], ""),
            "https://example.invalid/after" => (200, [], "fine"),
        )
        log = String[]
        with_online() do
            with_transport(recording_transport(responses; log)) do
                with_fast_limit() do
                    err = try
                        IstatApi._fetch(url429; cache = false)
                        nothing
                    catch e
                        e
                    end
                    @test err isa RateLimitError
                    @test err.retry_after == 60
                    sentinel = joinpath(cache_dir(), "banned_until")
                    @test isfile(sentinel)
                    until = tryparse(DateTime, strip(read(sentinel, String)))
                    @test until !== nothing
                    @test until - Dates.now(Dates.UTC) <= Dates.Second(61)

                    # next call: BannedError, transport untouched
                    n = length(log)
                    @test_throws BannedError IstatApi._fetch("https://example.invalid/after"; cache = false)
                    @test length(log) == n

                    clear_ban!()
                    @test IstatApi._fetch("https://example.invalid/after"; cache = false) == "fine"
                end
            end
        end
    end

    @testset "ambiguous 403 bans for one hour, not a day" begin
        url403 = "https://example.invalid/forbidden"
        with_online() do
            with_transport(recording_transport(Dict(url403 => (403, [], "")))) do
                with_fast_limit() do
                    @test_throws RequestFailed IstatApi._fetch(url403; cache = false)
                end
            end
        end
        sentinel = joinpath(cache_dir(), "banned_until")
        @test isfile(sentinel)
        until = tryparse(DateTime, strip(read(sentinel, String)))
        @test until !== nothing
        span = until - Dates.now(Dates.UTC)
        @test Dates.Minute(30) <= span <= Dates.Minute(61)
        clear_ban!()
    end

    @testset "an expired or garbled sentinel clears itself" begin
        sentinel = joinpath(cache_dir(), "banned_until")
        write(sentinel, string(Dates.now(Dates.UTC) - Dates.Hour(1)))
        IstatApi._check_ban!()          # expired → removed, no throw
        @test !isfile(sentinel)
        write(sentinel, "not a datetime")
        IstatApi._check_ban!()
        @test !isfile(sentinel)
    end

    @testset "retry = false actually reaches HTTP.jl" begin
        hits = Ref(0)
        port, tcpserver = Sockets.listenany(Sockets.localhost, 49500)
        server = HTTP.serve!(; server = tcpserver) do req
            hits[] += 1
            return HTTP.Response(503, "unavailable")
        end
        try
            status, _, _ = IstatApi._http_get("http://127.0.0.1:$port/x", "text/plain")
            @test status == 503
            # 503 is in HTTP.jl's default retryable set: with its default
            # `retry = true` this would be 4 hits, not 1.
            @test hits[] == 1
        finally
            close(server)
        end
    end
end
