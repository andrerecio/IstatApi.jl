# Dataflow catalogue: shipped snapshots + zero-request lookups.
#
# data/dataflows_IT1.csv and data/datastructures_IT1.csv are trimmed products
# of the two catalogue requests (/dataflow/IT1 and /datastructure/IT1) and ship
# with the package, so discovery, search and key construction cost zero
# requests. Resolution order: a refreshed copy in the cache dir → the shipped
# snapshot → refresh = true (one live request, written to the cache, which then
# shadows the snapshot). Snapshots are lazy-loaded on first use — never in
# __init__ and never during precompilation.

const _CATALOGUE_CACHE = Dict{String,DataFrame}()
const _SNAPSHOT_WARNED = Ref(false)

_data_dir() = joinpath(pkgdir(@__MODULE__), "data")

# Everything routes through here so a future migration of the shipped files to
# an Artifact is mechanical. Returns (path, shipped::Bool).
function _catalogue_path(name::AbstractString)
    user = joinpath(cache_dir(), name)
    isfile(user) && return (user, false)
    return (joinpath(_data_dir(), name), true)
end

function _load_catalogue(name::AbstractString)
    path, shipped = _catalogue_path(name)
    isfile(path) ||
        throw(ArgumentError("no catalogue snapshot $name — for agencies other " *
                            "than IT1 fetch one with refresh = true"))
    df = CSV.read(path, DataFrame; types = String, missingstring = nothing,
                  pool = false)
    if "position" in names(df)
        df.position = parse.(Int, df.position)
    end
    shipped && _warn_if_stale(path)
    return df
end

_catalogue(name::AbstractString) = get!(() -> _load_catalogue(name), _CATALOGUE_CACHE, name)

# One-time nudge if the shipped snapshot is old and the user never refreshed.
function _warn_if_stale(path::AbstractString)
    _SNAPSHOT_WARNED[] && return
    meta = path * ".meta.toml"
    isfile(meta) || return
    date = tryparse(Date, string(get(TOML.parsefile(meta), "snapshot_date", "")))
    date === nothing && return
    if today() - date > Day(180)
        _SNAPSHOT_WARNED[] = true
        @info "IstatApi's shipped catalogue snapshot is from $date. " *
              "`get_dataflows(refresh = true)` updates it with one live request."
    end
    return
end

# Parses the /dataflow/{agency} SDMX-JSON message into the snapshot schema.
function _parse_dataflows_json(body)
    flows = JSON3.read(body).data.dataflows
    df = DataFrame(id = String[], agency = String[], version = String[],
                   name_en = String[], name_it = String[],
                   dsd = String[], dsd_version = String[],
                   last_update = String[], metadata_url = String[])
    for f in flows
        flownames = get(f, :names, nothing)
        m = _urn_ref(get(f, :structure, ""))
        last_update, metadata_url = "", ""
        for a in get(f, :annotations, ())
            t = get(a, :type, "")
            t == "LAST_UPDATE" && (last_update = String(get(a, :title, "")))
            t == "METADATA_URL" && (metadata_url = String(get(a, :title, "")))
        end
        push!(df, (id = String(f.id), agency = String(f.agencyID),
                   version = String(f.version),
                   name_en = flownames === nothing ? String(get(f, :name, "")) :
                             String(get(flownames, :en, "")),
                   name_it = flownames === nothing ? "" :
                             String(get(flownames, :it, "")),
                   dsd = m === nothing ? "" : String(m[2]),
                   dsd_version = m === nothing ? "" : String(m[3]),
                   last_update, metadata_url))
    end
    return sort!(df, :id)
end

# "urn:...=AGENCY:ID(VERSION)" → RegexMatch with agency, id, version.
_urn_ref(urn) = match(r"=([A-Za-z0-9_]+):([A-Za-z0-9_.]+)\(([^)]+)\)", String(urn))

function _refresh_catalogue!(name::AbstractString, url::AbstractString, parser)
    body = _fetch(url; accept = "application/json", force = true)
    df = parser(body)
    dest = joinpath(cache_dir(), name)
    CSV.write(dest * ".part", df)
    mv(dest * ".part", dest; force = true)
    open(dest * ".meta.toml", "w") do io
        TOML.print(io, Dict("snapshot_date" => string(today()),
                            "rows" => nrow(df), "source" => url))
    end
    _CATALOGUE_CACHE[name] = df
    return df
end

"""
    get_dataflows(; agency = "IT1", refresh = false) -> DataFrame

Every dataflow the agency publishes — **zero requests**: served from the
catalogue snapshot shipped with the package (or a refreshed copy in the cache
dir, which shadows it). Columns: `id`, `agency`, `version`, `name_en`,
`name_it`, `dsd`, `dsd_version`, `last_update`, `metadata_url`.

`refresh = true` re-downloads the catalogue (one live request against ISTAT's
5-requests/minute budget) and caches it for all future sessions.
"""
function get_dataflows(; agency::AbstractString = "IT1", refresh::Bool = false)
    name = "dataflows_$(agency).csv"
    refresh && _refresh_catalogue!(name, string(ENDPOINT[], "/dataflow/", agency),
                                   _parse_dataflows_json)
    return copy(_catalogue(name))
end

"""
    get_dataflow(flow; agency = "IT1") -> DataFrameRow

The catalogue row for one dataflow — zero requests. `flow` may be a bare id
(`"115_333"`), the explicit `"IT1,115_333,1.0"` form, or the
`"IT1:115_333(1.0)"` form found in the `DATAFLOW` column of results, so query
results round-trip. Unknown ids throw `ArgumentError`.

# Examples
```jldoctest
julia> get_dataflow("115_333").name_en
"Industrial production index"

julia> get_dataflow("IT1:115_333(1.0)").dsd
"DCSC_INDXPRODIND_1"
```
"""
function get_dataflow(flow::AbstractString; agency::AbstractString = "IT1")
    parts = split(_flow_ref(flow; agency), ',')
    flow_agency, id = String(parts[1]), String(parts[2])
    df = _catalogue("dataflows_$(flow_agency).csv")
    i = findfirst(==(id), df.id)
    i === nothing &&
        throw(ArgumentError("no dataflow $id in the $flow_agency catalogue — " *
                            "try search_dataflow(\"...\")"))
    return df[i, :]
end
