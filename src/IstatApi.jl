"""
    IstatApi

A Julia client for ISTAT's SDMX 2.1 REST API
(`https://esploradati.istat.it/SDMXWS/rest`).

The service allows **5 requests per minute per IP** and blocks offenders for
1–2 days. The package is organised around never wasting a request: shipped
catalogue snapshots make discovery and key construction work offline, responses
are cached persistently, and a cross-process rate limiter plus a persisted ban
sentinel guard every request that does go out.
"""
module IstatApi

using CSV
using DataFrames
using Dates
using FileWatching: Pidfile
using HTTP
using JSON3
using Preferences
using SHA
using Scratch
using TOML
using Unicode

# Errors
export IstatError, OfflineError, BudgetExhaustedError, RateLimitError,
       BannedError, NoDataError, RequestFailed
# Offline mode
export offline!, online!, isoffline
# Cache
export cache_dir, set_cache_dir!, clear_cache!, cache_index
# Rate limiting and budget
export set_rate_limit!, rate_limit, with_budget, requests_used, clear_ban!
# Keys and parsing
export sdmx_key, sdmx_url, read_sdmx_csv
# Discovery (zero requests, shipped snapshot)
export get_dataflows, get_dataflow, search_dataflow, get_dimensions

include("errors.jl")
include("config.jl")
include("transport.jl")
include("ratelimit.jl")
include("cache.jl")
include("periods.jl")
include("keys.jl")
include("sdmxcsv.jl")
include("dataflows.jl")
include("search.jl")
include("structure.jl")
include("data.jl")
include("reshape.jl")
include("indicators.jl")

function __init__()
    # Honour ISTATAPI_OFFLINE at load time so test suites and CI can forbid
    # network access before any package code runs.
    if lowercase(get(ENV, "ISTATAPI_OFFLINE", "")) in ("1", "true", "yes")
        _OFFLINE[] = true
    end
    return nothing
end

end # module
