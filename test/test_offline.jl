@testset "offline guarantee" begin
    # runtests.jl set ISTATAPI_OFFLINE=1 before `using IstatApi`; __init__ must
    # have picked it up.
    @test isoffline()

    online!()
    @test !isoffline()
    offline!()
    @test isoffline()

    # The tests must never touch the user's real cache.
    @test haskey(ENV, "ISTATAPI_CACHE_DIR")
    @test isdir(ENV["ISTATAPI_CACHE_DIR"])
end
