# Retrieving data

[`get_data`](@ref) is the only function that spends a request on observations.
This page covers its options; the SDMX key mechanics are on the
[SDMX keys](keys.md) page.

## Two forms

```julia
# dimension keywords, validated against the DSD before any request
get_data("115_333"; FREQ = "M", REF_AREA = "IT", DATA_TYPE = "IND_PROD_21",
         ADJUSTMENT = "Y", ECON_ACTIVITY_NACE_2007 = ["0020", "0040"])

# a ready-made key (see sdmx_key) — same options, no validation
get_data("115_333", "M.IT.IND_PROD_21.Y.0020+0040")
```

Both return the same long/tidy `DataFrame`: `DATAFLOW`, one `String` column
per dimension, `TIME_PERIOD` (verbatim), `period::Date` (period start),
`freq::String`, `OBS_VALUE::Union{Float64,Missing}` (`missing`, never `NaN`),
then the status/note columns.

## Bounding the query

| Option | Server parameter | Notes |
|---|---|---|
| `from = "2015"` | `startPeriod` | any `TIME_PERIOD` shape (`2015`, `2015-Q1`, `2015-06`) |
| `to = "2024-12"` | `endPeriod` | ISTAT over-returns up to a year; `trim = true` (default) drops the excess locally |
| `last_n = 12` | `lastNObservations` | **per series** — a wildcard key returns the last 12 points of every series |
| `first_n = 3` | `firstNObservations` | likewise |

`last_n` is the cheapest way to look at an unfamiliar flow: one request, a
small body, and every series represented.

## The size guard

A **fully wildcarded** key (`get_data("115_333")`, or the key `"...."`) can
select a whole flow — hundreds of thousands of rows and an HTTP 413. Before
sending it, `get_data` sizes the query with one ~3 KB [`nobs`](@ref) request
and throws an `ArgumentError` above `max_obs` (default 100 000). Narrow the
key with dimension keywords, pass `last_n`, or override with
`max_obs = nothing`. Bounded queries (`last_n`/`first_n`) skip the check.

Partially wildcarded keys are not sized automatically — that would cost an
extra request on the most common query shape. Call `nobs` yourself when in
doubt:

```julia
nobs("115_333"; FREQ = "M", ADJUSTMENT = "Y")   # keywords …
nobs("115_333", "M...Y.")                        # … or a key
```

## Labels

```julia
get_data("115_333"; FREQ = "M", ADJUSTMENT = "Y", labels = true)      # local join
get_data("115_333"; FREQ = "M", ADJUSTMENT = "Y", labels = :server)   # ;labels=both
```

Both add a `<DIM>_label` column right after each dimension column, so the
schema is identical and [`to_wide`](@ref) / [`to_timearray`](@ref) work on
either. `labels = true` joins English labels **locally** from the cached
codelists (one `get_datastructure` request the first time, free after);
`:server` costs no structure request but roughly triples the wire size and
is not cached together with the unlabelled response.

## Cache and force

Every response is cached persistently by URL and `Accept` header; a repeat
call is a cache hit that never touches the rate limiter. `cache = false`
skips reading *and* writing; `force = true` refetches and overwrites. See
[Rate limits, cache and offline mode](rate_limits.md).

## Reshaping

```julia
to_wide(df)                    # period + one column per varying-dimension combination
to_wide(df; by = ["ECON_ACTIVITY_NACE_2007"])
using TimeSeries
to_timearray(df)               # TimeArray via the package extension
```

Both error if more than one `freq` is present — filter to one frequency first
rather than silently misaligning periods.
