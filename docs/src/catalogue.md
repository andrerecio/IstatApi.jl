# The catalogue

Discovery costs **zero requests**. Two snapshots ship with the package —
`data/dataflows_IT1.csv` (every dataflow: id, names in English and Italian,
DSD reference, last update) and `data/datastructures_IT1.csv` (the ordered
dimension list of every DSD) — and everything below is served from them.

```julia
get_dataflows()                     # the whole catalogue as a DataFrame
get_dataflow("115_333")             # one row; accepts "IT1:115_333(1.0)" too
search_dataflow("prezzi al consumo") # ranked, accent-insensitive, EN + IT
get_dimensions("115_333")           # ordered dimension names — the key template
sdmx_key(get_dimensions("115_333"); FREQ = "M")   # "M...."
```

Search order is deterministic: score descending, then `id` ascending.

## Refreshing

The snapshots are trimmed products of two catalogue requests (`/dataflow/IT1`
and `/datastructure/IT1`). To update them:

```julia
get_dataflows(refresh = true)       # one live request
get_dimensions("115_333"; refresh = true)
```

A refreshed copy is written to the cache directory and shadows the shipped
file for every future session — until `clear_cache!(what = :catalogue)`
removes it. When the shipped snapshot is older than about six months and you
have never refreshed, the package prints a one-time `@info` nudge.

Snapshots are loaded lazily on first use, never at package load time.

## What is *not* in the snapshot

Codelists (the code → label tables) are too large to ship for 892 DSDs. They
arrive with [`get_datastructure`](@ref) — one request per DSD, memoised in
memory and cached on disk — and feed [`get_codelist`](@ref) and the local
label join in [`get_data`](@ref) (`labels = true`).

A codelist holds every code the agency defines; most flows use a fraction.
[`available`](@ref) asks the server which codes **actually have data** under
a partial key (~3 KB per call), and [`nobs`](@ref) returns the observation
count of a key — the two tools for narrowing a query before paying for it.
