# Live smoke tests — the ONLY file that touches the service.
#
#     julia --project test/live_tests.jl
#
# Never run by runtests.jl, never run in CI. Costs a handful of requests under
# the live throttle (~1 min); cached responses cost nothing on re-runs.

if lowercase(get(ENV, "ISTATAPI_OFFLINE", "")) in ("1", "true", "yes")
    error("live_tests.jl needs the network; unset ISTATAPI_OFFLINE")
end

using IstatApi
using DataFrames
using Test

@testset "live" begin
    # the shipped snapshot's structural facts still hold
    @test get_dimensions("115_333") == ["FREQ", "REF_AREA", "DATA_TYPE",
                                        "ADJUSTMENT", "ECON_ACTIVITY_NACE_2007"]

    # availability answers with a small request
    @test nobs("115_333"; FREQ = "M", ADJUSTMENT = "Y") > 100_000
    av = available("115_333", "ECON_ACTIVITY_NACE_2007"; FREQ = "M", ADJUSTMENT = "Y")
    @test "0020" in av.code

    # the curated shortcut still resolves
    df = industrial_production(from = "2026-01")
    @test nrow(df) > 0
    @test all(==("M"), df.freq)
    @test df.ECON_ACTIVITY_NACE_2007 == fill("0020", nrow(df))

    println("live smoke OK — requests used this session: ", requests_used())
end
