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
        clear_cache!()
        rm(logfile; force = true)
    end
end
