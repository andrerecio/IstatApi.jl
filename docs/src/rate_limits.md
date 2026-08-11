# Rate limits, cache and offline mode

ISTAT allows **5 requests per minute per IP** and blocks offenders for **1–2
days**. IstatApi is built so you rarely spend a request at all, and never
spend one by accident.

## What never costs a request

- Catalogue search and lookup (`search_dataflow`, `get_dataflows`,
  `get_dataflow`) — served from snapshots shipped with the package.
- Dimension lists and key construction (`get_dimensions`, `sdmx_key`).
- Anything already in the **response cache**: responses persist across
  sessions, and cache hits never touch the rate limiter.

## The throttle

Requests that do go out pass a cross-process limiter: at least 15 s between
requests and at most 4 per rolling minute (a margin under the official
limit). The state lives in the cache directory, so parallel Julia sessions,
Pluto notebooks and Quarto renders on the same machine share one budget —
which is what the server sees anyway.

```julia
rate_limit()                    # (interval = 15.0, per_minute = 4)
set_rate_limit!(interval = 20)  # loosen/tighten at your own risk
requests_used()                 # requests actually sent this session
```

`with_budget(f, n)` makes a script's cost explicit — the `n+1`-th request
throws `BudgetExhaustedError` before touching the network:

```julia
with_budget(2) do
    gdp()
end
```

## If you do get blocked

A 429 (or an ambiguous 403) writes a **ban sentinel** that persists across
sessions; while it is live every request throws `BannedError` without
touching the network, because hammering a service that blocked you extends
the block. `clear_ban!()` removes it once you are confident the block has
lapsed.

## Offline mode

```julia
IstatApi.offline!()    # cache misses now throw OfflineError instead of fetching
IstatApi.online!()
```

Or set `ISTATAPI_OFFLINE=1` before loading the package — this is how the
package's own test suite guarantees it never makes a request.

## Cache control

```julia
cache_dir()                        # where everything lives (a Pkg scratchspace)
cache_index()                      # one row per cached response
clear_cache!(older_than = Day(90)) # prune old entries
set_cache_dir!(path)               # or ISTATAPI_CACHE_DIR / a Preference
```
