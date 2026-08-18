# IstatApi.jl

A Julia client for [ISTAT](https://www.istat.it)'s SDMX 2.1 REST API.

!!! note "Pre-registration"
    Version 0.1.0 is implemented and tested but not yet in the General
    registry — install with `Pkg.add(url = "https://github.com/andrerecio/IstatApi.jl")`.

ISTAT's service allows **5 requests per minute per IP** and blocks offenders
for 1–2 days. IstatApi.jl is designed around never wasting a request: dataset
discovery and search run offline against catalogue snapshots shipped with the
package, responses are cached persistently, and a cross-process rate limiter
guards every request that does go out.

## Offline mode

```julia
using IstatApi

IstatApi.offline!()   # cache misses now throw OfflineError instead of fetching
IstatApi.online!()    # back to normal (the default)
```

Offline mode can also be forced from the environment with `ISTATAPI_OFFLINE=1`,
set before the package is loaded.
