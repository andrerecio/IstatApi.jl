# Global configuration: endpoint and offline mode.
#
# Cache-directory resolution (ISTATAPI_CACHE_DIR → Preferences → Scratch.jl)
# lives in cache.jl; rate-limit settings live in ratelimit.jl.

# Not exported (use qualified): the endpoint is a Ref so tests and mirrors can
# swap it without recompilation.
const ENDPOINT = Ref{String}("https://esploradati.istat.it/SDMXWS/rest")

"""
    set_endpoint!(url)

Point the client at a different SDMX 2.1 REST endpoint (not exported; the
default is ISTAT's `https://esploradati.istat.it/SDMXWS/rest`).
"""
set_endpoint!(url::AbstractString) = (ENDPOINT[] = String(url); nothing)

const _OFFLINE = Ref{Bool}(false)

"""
    offline!()

Enter offline mode: any operation that would touch the network throws
[`OfflineError`](@ref) instead. Everything served from the cache or the shipped
catalogue snapshots keeps working. Also enabled by setting `ISTATAPI_OFFLINE=1`
in the environment before loading the package.

See also [`online!`](@ref), [`isoffline`](@ref).
"""
offline!() = (_OFFLINE[] = true; nothing)

"""
    online!()

Leave offline mode (the default). See [`offline!`](@ref).
"""
online!() = (_OFFLINE[] = false; nothing)

"""
    isoffline() -> Bool

Whether offline mode is active. See [`offline!`](@ref).
"""
isoffline() = _OFFLINE[]
