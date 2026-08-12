# IstatApi.jl

[![CI](https://github.com/andrerecio/IstatApi.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/andrerecio/IstatApi.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/andrerecio/IstatApi.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/andrerecio/IstatApi.jl)
[![Docs: dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://andrerecio.github.io/IstatApi.jl/dev/)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A Julia client for [ISTAT](https://www.istat.it)'s SDMX REST API — the
official data service of the Italian National Institute of Statistics.

> ⚠️ **Pre-registration.** The v0.1.0 surface is implemented and tested, but
> the package is not yet registered and the API may still change until the
> first tag.

ISTAT allows **5 requests per minute per IP** and blocks offenders for 1–2
days. IstatApi.jl is designed around never wasting a request:

- **Offline discovery.** The full catalogue (4,896 dataflows and every DSD's
  dimension order) ships with the package — searching, inspecting dimensions
  and building keys cost **zero requests** and work without a network.
- **Persistent caching.** Responses are cached across sessions; cache hits
  never touch the rate limiter.
- **A cross-process throttle and ban sentinel.** Parallel Julia sessions on
  one machine share a single request budget, and a 429 persists a sentinel so
  no process keeps hammering a service that has blocked you.
- **Query sizing before fetching.** `nobs`/`available` answer "how big is
  this query" and "which codes have data here" with ~3 KB requests.

## Quick start

```julia
using IstatApi

search_dataflow("industrial production")     # offline, ranked, EN + IT
get_dimensions("115_333")                    # offline: the key template

df = get_data("115_333";                     # one throttled, cached request
              FREQ = "M", REF_AREA = "IT", DATA_TYPE = "IND_PROD_21",
              ADJUSTMENT = "Y", ECON_ACTIVITY_NACE_2007 = ["0020", "C"],
              from = "2015")

to_wide(df)                                  # one column per series
```

Or the curated shortcuts, each documented as the exact `get_data` call it
wraps: `industrial_production()`, `gdp()`, `consumer_prices()`,
`unemployment()`.

Results are long/tidy `DataFrame`s: SDMX codes stay `String`s (`"0020"` never
becomes `20`), absent values are `missing`, and each row carries
`period::Date` (period start) plus `freq` alongside the verbatim
`TIME_PERIOD`. `using TimeSeries` enables `to_timearray`.

For a commented start-to-finish walkthrough (discover → inspect → filter →
retrieve), run [`examples/basic_usage.jl`](examples/basic_usage.jl):

```bash
julia --project examples/basic_usage.jl
```

## When to use something else

- [DBnomics.jl](https://github.com/s915/DBnomics.jl) mirrors ISTAT (among
  many providers) with no per-IP limit. Prefer it for casual cross-provider
  work; prefer IstatApi.jl for the official endpoint, the full current
  catalogue, ISTAT's own codes and labels, and control over which codelist
  vintage you get.
- [SDMX.jl](https://github.com/kafisatz/SDMX.jl) reads SDMX-JSON files you
  already have; it is a parser, not a client.

## License

MIT — see [LICENSE](LICENSE).
