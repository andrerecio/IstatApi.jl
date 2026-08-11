# Live smoke tests — the ONLY file that touches the service.
#
#     julia --project test/live_tests.jl
#
# Never run by runtests.jl, never run in CI. Costs a handful of requests under
# the live throttle (~2 min cold); cached responses cost nothing on re-runs.

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

    # every curated shortcut still resolves (each may drift when ISTAT
    # revises its dataflow — see the docstrings for the fallback get_data call)
    ipi = industrial_production(from = "2026-01")
    @test nrow(ipi) > 0 && all(==("M"), ipi.freq)

    q = gdp(from = "2025-01")
    @test nrow(q) > 0 && all(==("Q"), q.freq)
    @test length(unique(q.EDITION)) == 1

    cpi = consumer_prices()
    @test nrow(cpi) > 0 && cpi.ECOICOP_2 == fill("00", nrow(cpi))

    u = unemployment(from = "2026-01")
    @test nrow(u) > 0 && all(v -> ismissing(v) || 0 < v < 50, u.OBS_VALUE)

    println("live smoke OK — requests used this session: ", requests_used())
end
