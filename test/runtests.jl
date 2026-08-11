# The offline guarantee, layer 1: set BEFORE `using IstatApi`, so the package
# can never touch the network or the user's real cache during tests. Layer 2 is
# the fixture transport (swapped into IstatApi._TRANSPORT[] once it exists);
# layer 3 is the first testset below, which asserts the guarantee itself.
ENV["ISTATAPI_OFFLINE"] = "1"
ENV["ISTATAPI_CACHE_DIR"] = mktempdir()

using IstatApi
using Test
using Dates
using DataFrames
using HTTP

include("helpers.jl")

@testset "IstatApi.jl" begin
    include("test_offline.jl")
    include("test_errors.jl")
    include("test_periods.jl")
    include("test_keys.jl")
    include("test_sdmxcsv.jl")
    include("test_dataflows.jl")
    include("test_search.jl")
    include("test_structure.jl")
    include("test_data.jl")
    include("test_reshape.jl")
    include("test_indicators.jl")
    include("test_cache.jl")
    include("test_ratelimit.jl")
    include("test_transport.jl")
    include("test_aqua.jl")
end
