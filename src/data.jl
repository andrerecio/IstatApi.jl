# Data retrieval.

const _ACCEPT_CSV = "application/vnd.sdmx.data+csv;version=1.0.0"

"""
    get_data(flow; from = nothing, to = nothing, last_n = nothing, first_n = nothing,
             trim = true, labels = false, cache = true, force = false,
             max_obs = 100_000, agency = "IT1", DIMS...) -> DataFrame
    get_data(flow, key::AbstractString; <same options>) -> DataFrame

Fetch observations from `flow`. Uppercase keywords select dimension codes
(scalar or vector — a vector is one `+`-joined request, never a loop) and are
validated against the DSD; lowercase keywords are options. The second form
takes a ready-made key (see [`sdmx_key`](@ref)) and skips validation.

Returns a long/tidy `DataFrame`: `DATAFLOW`, one `String` column per
dimension, `TIME_PERIOD` (verbatim), `period::Date` (period start),
`freq::String`, `OBS_VALUE::Union{Float64,Missing}`, then the status/note
columns.

- `from`/`to` become `startPeriod`/`endPeriod`. ISTAT's `endPeriod` may return
  up to one extra year; with `trim = true` (default) observations after `to`
  are dropped locally so the bound is exact.
- `last_n`/`first_n` become `lastNObservations`/`firstNObservations` — the
  cheapest way to peek at a flow (`last_n = 12` on a wildcard key returns the
  last twelve points of *every* series in one request).
- `labels = true` joins English labels **locally** from the cached codelists
  (one `get_datastructure` request the first time, free after) as
  `<DIM>_label` columns — avoiding the ~3× wire cost of server-side labels.
  `labels = :server` asks the server instead (`;labels=both`, one round trip,
  no DSD needed) — the `"CODE: label"` cells are split back into the code
  column plus a `<DIM>_label` column, so both forms have the same schema.
- A **fully wildcarded** key (either form) first sizes itself with
  [`nobs`](@ref) and refuses above `max_obs` observations — unless
  `last_n`/`first_n` bounds it already. Pass `max_obs = nothing` to override.
- Responses are cached persistently; cache hits cost zero requests and never
  touch the rate limiter. `force = true` refetches.
"""
function get_data(flow::AbstractString; agency::AbstractString = "IT1",
                  from = nothing, to = nothing,
                  last_n::Union{Nothing,Integer} = nothing,
                  first_n::Union{Nothing,Integer} = nothing,
                  trim::Bool = true, labels = false,
                  cache::Bool = true, force::Bool = false,
                  max_obs::Union{Nothing,Integer} = 100_000, kwargs...)
    dims = get_dimensions(flow; agency)
    key = sdmx_key(dims; kwargs...)
    return get_data(flow, key; agency, from, to, last_n, first_n, trim, labels,
                    cache, force, max_obs)
end

function get_data(flow::AbstractString, key::AbstractString;
                  agency::AbstractString = "IT1", from = nothing, to = nothing,
                  last_n::Union{Nothing,Integer} = nothing,
                  first_n::Union{Nothing,Integer} = nothing,
                  trim::Bool = true, labels = false,
                  cache::Bool = true, force::Bool = false,
                  max_obs::Union{Nothing,Integer} = 100_000)
    labels in (false, true, :server) ||
        throw(ArgumentError("labels must be false, true or :server, got $labels"))
    bounded = last_n !== nothing || first_n !== nothing
    if max_obs !== nothing && !bounded && _is_fully_wildcarded(key)
        n = nobs(flow, key; agency)
        n > max_obs && throw(ArgumentError(
            "a fully wildcarded query on $flow selects $n observations " *
            "(max_obs = $max_obs). Narrow it with dimension keywords — " *
            "available(flow, dim) lists the codes that have data — pass " *
            "last_n to peek, or max_obs = nothing to fetch anyway."))
    end
    accept = labels === :server ? _ACCEPT_CSV * ";labels=both" : _ACCEPT_CSV
    url = sdmx_url(flow, key; from, to, last_n, first_n, agency)
    df = read_sdmx_csv(_fetch(url; accept, cache, force))
    labels === true && _join_labels!(df, flow; agency)
    trim && to !== nothing && _trim_to!(df, to)
    return df
end

# endPeriod is documented (and observed) to over-return: drop rows that start
# after the last day of `to`. An unparseable `to` is left to the server.
function _trim_to!(df::AbstractDataFrame, to)
    cutoff = try
        parse_period(string(to); at = :last)
    catch
        return df
    end
    return filter!(r -> r.period <= cutoff, df)
end

# English labels from the cached codelists, inserted as <DIM>_label columns.
# Free once the DSD is cached — the genuine advantage over `;labels=both`.
function _join_labels!(df::AbstractDataFrame, flow::AbstractString;
                       agency::AbstractString = "IT1")
    ds = get_datastructure(flow; agency)
    for dim in reverse(ds.dimensions)      # reverse keeps earlier indices valid
        i = findfirst(==(dim), names(df))
        i === nothing && continue
        cl = get(ds.codelist_of, dim, "")
        haskey(ds.codelists, cl) || continue
        codes = ds.codelists[cl]
        lookup = Dict(zip(codes.code, codes.name_en))
        insertcols!(df, i + 1,
            Symbol(dim, :_label) => String[get(lookup, c, "") for c in df[!, dim]])
    end
    return df
end
