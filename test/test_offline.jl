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

    # Offline mode stops the public data path before the transport: a cache
    # miss throws OfflineError and the transport is never called.
    log = String[]
    with_transport(recording_transport(Dict{String,Any}(); log)) do
        @test_throws OfflineError get_data("115_333"; FREQ = "M", REF_AREA = "IT",
                                           DATA_TYPE = "IND_PROD_21", ADJUSTMENT = "Y",
                                           ECON_ACTIVITY_NACE_2007 = "0020")
        @test_throws OfflineError get_data("115_333", "M.IT.IND_PROD_21.Y.0020")
        @test_throws OfflineError available("115_333", "FREQ")
        @test_throws OfflineError get_datastructure("115_333")
    end
    @test isempty(log)
end
