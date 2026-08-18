@testset "cache" begin
    # runtests.jl pointed the cache at a temp dir before `using IstatApi`.
    @test cache_dir() == abspath(ENV["ISTATAPI_CACHE_DIR"])

    @testset "set_cache_dir! redirects without persisting" begin
        old = cache_dir()
        tmp2 = mktempdir()
        set_cache_dir!(tmp2)
        @test cache_dir() == abspath(tmp2)
        set_cache_dir!(old)
        @test cache_dir() == old
    end

    @testset "set_cache_dir!(persist = true) writes and honours the preference" begin
        old = cache_dir()
        tmp3 = mktempdir()
        try
            set_cache_dir!(tmp3; persist = true)
            @test IstatApi.load_preference(IstatApi, "cache_dir") == abspath(tmp3)
            # resolution order: env var still wins over the preference …
            @test IstatApi._resolve_cache_dir() == abspath(ENV["ISTATAPI_CACHE_DIR"])
            # … and the preference wins once the env var is gone
            withenv("ISTATAPI_CACHE_DIR" => nothing) do
                @test IstatApi._resolve_cache_dir() == abspath(tmp3)
            end
        finally
            IstatApi.delete_preferences!(IstatApi, "cache_dir"; force = true)
            set_cache_dir!(old)
        end
        @test IstatApi.load_preference(IstatApi, "cache_dir", nothing) === nothing
        @test cache_dir() == old
    end

    @testset "write / read roundtrip" begin
        IstatApi._cache_write("https://example.invalid/x", "text/csv", 200, "hello")
        @test IstatApi._cache_read("https://example.invalid/x", "text/csv") == "hello"
        # a different Accept is a different cache entry
        @test IstatApi._cache_read("https://example.invalid/x", "application/json") === nothing
        # no stray .part files after the atomic write
        @test !any(endswith(".part"), readdir(cache_dir()))

        idx = cache_index()
        @test "https://example.invalid/x" in idx.url
        row = idx[findfirst(==("https://example.invalid/x"), idx.url), :]
        @test row.status == 200
        @test row.bytes == 5
    end

    @testset "hashed names survive 2000-character keys" begin
        longurl = "https://example.invalid/data/IT1,115_333/" *
                  join(("A$i" for i in 1:500), "+")
        @test length(longurl) > 2000
        path = IstatApi._cache_path(longurl, "text/csv")
        @test length(basename(path)) < 100
        IstatApi._cache_write(longurl, "text/csv", 200, "big-key")
        @test IstatApi._cache_read(longurl, "text/csv") == "big-key"
    end

    @testset "clear_cache! spares limiter state" begin
        logfile = joinpath(cache_dir(), "requests.log")
        write(logfile, "1.0\n")
        n = clear_cache!()
        @test n >= 2                       # at least one body + one sidecar
        @test isfile(logfile)
        @test isempty(cache_index())

        IstatApi._cache_write("https://example.invalid/y", "text/csv", 200, "fresh")
        @test clear_cache!(older_than = Dates.Day(1)) == 0
        @test IstatApi._cache_read("https://example.invalid/y", "text/csv") == "fresh"
        # older_than really deletes once the file is old enough
        sleep(0.1)
        @test clear_cache!(older_than = Dates.Millisecond(10)) >= 2
        @test IstatApi._cache_read("https://example.invalid/y", "text/csv") === nothing
        clear_cache!()
        rm(logfile; force = true)
    end

    @testset "clear_cache!(what = ...) sweeps one kind at a time" begin
        ep = IstatApi.ENDPOINT[]
        IstatApi._cache_write("$ep/data/IT1,115_333/M...Y.", "text/csv", 200, "d")
        IstatApi._cache_write("$ep/datastructure/IT1/X/1.0?references=children", "application/json", 200, "s")
        IstatApi._cache_write("$ep/availableconstraint/115_333/...../all/FREQ", "application/xml", 200, "a")
        IstatApi._cache_write("$ep/dataflow/IT1", "application/json", 200, "f")
        write(joinpath(cache_dir(), "dataflows_IT1.csv"), "id\n")
        write(joinpath(cache_dir(), "dataflows_IT1.csv.meta.toml"), "rows = 1\n")
        @test_throws ArgumentError clear_cache!(what = :everything)
        @test clear_cache!(what = :data) == 2                  # body + sidecar
        @test IstatApi._cache_read("$ep/data/IT1,115_333/M...Y.", "text/csv") === nothing
        @test IstatApi._cache_read("$ep/dataflow/IT1", "application/json") == "f"
        @test clear_cache!(what = :structure) == 4             # DSD + availability
        @test isfile(joinpath(cache_dir(), "dataflows_IT1.csv"))
        @test clear_cache!(what = :catalogue) == 4             # /dataflow pair + csv + toml
        @test isempty(cache_index())
        clear_cache!()
    end
end
