# Data retrieval.

const _ACCEPT_CSV = "application/vnd.sdmx.data+csv;version=1.0.0"

"""
    get_data(flow; from = nothing, to = nothing, labels = false, cache = true,
             force = false, max_obs = 100_000, agency = "IT1", DIMS...) -> DataFrame
    get_data(flow, key::AbstractString; from, to, labels, cache, force, agency) -> DataFrame

Fetch observations from `flow`. Uppercase keywords select dimension codes
(scalar or vector — a vector is one `+`-joined request, never a loop) and are
validated against the DSD; lowercase keywords are options. The second form
takes a ready-made key (see [`sdmx_key`](@ref)) and skips validation.

Returns a long/tidy `DataFrame`: `DATAFLOW`, one `String` column per
dimension, `TIME_PERIOD` (verbatim), `period::Date` (period start),
`freq::String`, `OBS_VALUE::Union{Float64,Missing}`, then the status/note
columns.

- `labels = true` joins English labels **locally** from the cached codelists
  (one `get_datastructure` request the first time, free after) as
  `<DIM>_label` columns — avoiding the ~3× wire cost of server-side labels.
  `labels = :server` asks the server instead (`;labels=both`, one round trip,
  no DSD needed; note it relabels the CSV headers to `"CODE: label"` form).
- A **fully wildcarded** query first sizes itself with [`nobs`](@ref) and
  refuses above `max_obs` observations; pass `max_obs = nothing` to override.
- `from`/`to` become `startPeriod`/`endPeriod` (ISTAT's `endPeriod` may return
  up to one extra year — trim after parsing if the boundary matters).
- Responses are cached persistently; cache hits cost zero requests and never
  touch the rate limiter. `force = true` refetches.
"""
function get_data(flow::AbstractString; agency::AbstractString = "IT1",
                  from = nothing, to = nothing, labels = false,
                  cache::Bool = true, force::Bool = false,
                  max_obs::Union{Nothing,Integer} = 100_000, kwargs...)
    dims = get_dimensions(flow; agency)
    key = sdmx_key(dims; kwargs...)
    if isempty(kwargs) && max_obs !== nothing
        n = nobs(flow; agency)
        n > max_obs && throw(ArgumentError(
            "a fully wildcarded query on $flow selects $n observations " *
            "(max_obs = $max_obs). Narrow it with dimension keywords — " *
            "available(flow, dim) lists the codes that have data — or pass " *
            "max_obs = nothing to fetch anyway."))
    end
    return get_data(flow, key; agency, from, to, labels, cache, force)
end

function get_data(flow::AbstractString, key::AbstractString;
                  agency::AbstractString = "IT1", from = nothing, to = nothing,
                  labels = false, cache::Bool = true, force::Bool = false)
    labels in (false, true, :server) ||
        throw(ArgumentError("labels must be false, true or :server, got $labels"))
    accept = labels === :server ? _ACCEPT_CSV * ";labels=both" : _ACCEPT_CSV
    url = sdmx_url(flow, key; from, to, agency)
    df = read_sdmx_csv(_fetch(url; accept, cache, force))
    labels === true && _join_labels!(df, flow; agency)
    return df
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
