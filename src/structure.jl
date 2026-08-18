# Data structures (DSDs), codelists and availability.
#
# Dimension lists come from the shipped snapshot (zero requests).
# get_datastructure costs one request (?references=children, a few MB) and is
# memoised; available/nobs wrap /availableconstraint — ~3 KB answers to "which
# codes have data HERE" and "how many observations would this key return",
# the package's best request-savers.

# Parses the /datastructure/{agency} SDMX-JSON message into the snapshot
# schema: one row per key dimension. The TimeDimension is not a key position
# and is deliberately excluded.
function _parse_datastructures_json(body)
    dsds = JSON3.read(body).data.dataStructures
    df = DataFrame(dsd = String[], version = String[], position = Int[],
                   dimension = String[], codelist = String[])
    for d in dsds
        for dim in d.dataStructureComponents.dimensionList.dimensions
            cl = ""
            rep = get(dim, :localRepresentation, nothing)
            if rep !== nothing
                m = _urn_ref(get(rep, :enumeration, ""))
                m === nothing || (cl = String(m[2]))
            end
            push!(df, (dsd = String(d.id), version = String(d.version),
                       position = Int(dim.position),
                       dimension = String(dim.id), codelist = cl))
        end
    end
    return sort!(df, [:dsd, :version, :position])
end

"""
    get_dimensions(flow; agency = "IT1", refresh = false) -> Vector{String}

The ordered key dimensions of `flow`'s data structure — **zero requests**,
from the shipped snapshot. This order is the law of the key: one position per
dimension, `.`-separated (the time dimension is not a key position).

`refresh = true` re-downloads the datastructure catalogue (one live request).

# Examples
```jldoctest
julia> get_dimensions("115_333")
5-element Vector{String}:
 "FREQ"
 "REF_AREA"
 "DATA_TYPE"
 "ADJUSTMENT"
 "ECON_ACTIVITY_NACE_2007"
```
"""
function get_dimensions(flow::AbstractString; agency::AbstractString = "IT1",
                        refresh::Bool = false)
    name = "datastructures_$(agency).csv"
    refresh && _refresh_catalogue!(name,
        string(ENDPOINT[], "/datastructure/", agency), _parse_datastructures_json)
    row = get_dataflow(flow; agency)
    ds = _catalogue(name)
    sub = ds[(ds.dsd .== row.dsd) .& (ds.version .== row.dsd_version), :]
    isempty(sub) &&
        throw(ArgumentError("datastructure $(row.dsd) v$(row.dsd_version) not in " *
                            "the snapshot — try get_dimensions(\"$flow\", refresh = true)"))
    sort!(sub, :position)
    return String.(sub.dimension)
end

"""
    sdmx_key(flow::AbstractString; agency = "IT1", DIMS...) -> String

Build a data key for `flow`, resolving its dimension order from the shipped
snapshot — zero requests. Uppercase keywords are dimensions (validated against
the DSD; a typo throws `ArgumentError` locally instead of wasting a request),
lowercase keywords are options.

# Examples
```jldoctest
julia> sdmx_key("115_333"; FREQ = "M", ECON_ACTIVITY_NACE_2007 = ["0020", "C"])
"M....0020+C"
```
"""
sdmx_key(flow::AbstractString; agency::AbstractString = "IT1", kwargs...) =
    sdmx_key(get_dimensions(flow; agency); kwargs...)

# --- full data structure with codelists --------------------------------------

"""
    DataStructure

One dataflow's data structure definition: the ordered key `dimensions`, the
`codelist_of` each dimension, the `codelists` themselves (`DataFrame`s with
`code`, `name_en`, `name_it`, `parent`) and the attribute ids. Displayed with
the key template, so `display(get_datastructure(flow))` answers "how do I
write the key".
"""
struct DataStructure
    agency::String
    id::String
    version::String
    dimensions::Vector{String}
    codelist_of::Dict{String,String}
    codelists::Dict{String,DataFrame}
    attributes::Vector{String}
end

function Base.show(io::IO, ::MIME"text/plain", ds::DataStructure)
    println(io, "DataStructure ", ds.agency, ":", ds.id, "(", ds.version, ")")
    println(io, "  key template: ", join(ds.dimensions, "."))
    for (i, d) in enumerate(ds.dimensions)
        cl = get(ds.codelist_of, d, "")
        n = haskey(ds.codelists, cl) ? nrow(ds.codelists[cl]) : 0
        hint = n >= 1000 ? " — large; available(flow, \"$d\") lists the codes with data" : ""
        println(io, "  ", lpad(i, 2), ". ", rpad(d, 26), " ", cl, " (", n, " codes)", hint)
    end
    print(io, "  attributes: ", join(ds.attributes, ", "))
end

function _parse_datastructure_children(body, agency::String)
    doc = JSON3.read(body)
    d = doc.data.dataStructures[1]
    comp = d.dataStructureComponents
    dims = sort(collect(comp.dimensionList.dimensions); by = x -> Int(x.position))
    dimensions = String[String(x.id) for x in dims]
    codelist_of = Dict{String,String}()
    for x in dims
        rep = get(x, :localRepresentation, nothing)
        rep === nothing && continue
        m = _urn_ref(get(rep, :enumeration, ""))
        m === nothing || (codelist_of[String(x.id)] = String(m[2]))
    end
    attributes = String[]
    attrlist = get(comp, :attributeList, nothing)
    if attrlist !== nothing
        append!(attributes, String(a.id) for a in get(attrlist, :attributes, ()))
    end
    codelists = Dict{String,DataFrame}()
    for cl in get(doc.data, :codelists, ())
        df = DataFrame(code = String[], name_en = String[], name_it = String[],
                       parent = String[])
        for c in get(cl, :codes, ())
            cnames = get(c, :names, nothing)
            push!(df, (code = String(c.id),
                       name_en = cnames === nothing ? String(get(c, :name, "")) :
                                 String(get(cnames, :en, "")),
                       name_it = cnames === nothing ? "" :
                                 String(get(cnames, :it, "")),
                       parent = String(get(c, :parent, ""))))
        end
        codelists[String(cl.id)] = df
    end
    return DataStructure(agency, String(d.id), String(d.version), dimensions,
                         codelist_of, codelists, attributes)
end

const _DSD_CACHE = Dict{String,DataStructure}()

"""
    get_datastructure(flow; agency = "IT1", refresh = false) -> DataStructure

The full data structure of `flow`, codelists included — **one request** the
first time (`?references=children`, a few MB), then memoised for the session
and served from the response cache across sessions. `display` the result to
see the key template.
"""
function get_datastructure(flow::AbstractString; agency::AbstractString = "IT1",
                           refresh::Bool = false)
    row = get_dataflow(flow; agency)
    memo = string(agency, ':', row.dsd, '(', row.dsd_version, ')')
    !refresh && haskey(_DSD_CACHE, memo) && return _DSD_CACHE[memo]
    url = string(ENDPOINT[], "/datastructure/", agency, "/", row.dsd, "/",
                 row.dsd_version, "?references=children")
    body = _fetch(url; accept = "application/json", force = refresh)
    ds = _parse_datastructure_children(body, String(agency))
    _DSD_CACHE[memo] = ds
    return ds
end

const _CODELIST_WARNED = Set{String}()

"""
    get_codelist(flow, dimension; lang = :both, agency = "IT1") -> DataFrame

The codelist of `dimension` in `flow` — costs one request the first time (it
rides along with [`get_datastructure`](@ref)). Columns: `code`, `name_en`
and/or `name_it` (per `lang`), `parent`.

!!! warning
    A codelist holds **every** code of that codelist, not only those with data
    in this dataflow — `CL_ATECO_2007` has 2,063 codes but only ~340 carry
    industrial-production data. [`available`](@ref) answers "which codes have
    data *here*" with a ~3 KB request.
"""
function get_codelist(flow::AbstractString, dimension::AbstractString;
                      lang::Symbol = :both, agency::AbstractString = "IT1")
    lang in (:en, :it, :both) ||
        throw(ArgumentError("lang must be :en, :it or :both, got :$lang"))
    ds = get_datastructure(flow; agency)
    dimension in ds.dimensions ||
        throw(ArgumentError("unknown dimension $dimension; $(ds.id) has " *
                            join(ds.dimensions, ", ")))
    cl = get(ds.codelist_of, dimension, "")
    haskey(ds.codelists, cl) ||
        throw(ArgumentError("no codelist in the response for $dimension ($cl)"))
    df = copy(ds.codelists[cl])
    if nrow(df) >= 1000 && !(cl in _CODELIST_WARNED)
        push!(_CODELIST_WARNED, cl)
        @warn "$cl has $(nrow(df)) codes — most may have no data in $(ds.id). " *
              "available(flow, \"$dimension\") lists only the codes that do."
    end
    lang === :en && select!(df, :code, :name_en, :parent)
    lang === :it && select!(df, :code, :name_it, :parent)
    return df
end

# --- availability ------------------------------------------------------------

# /availableconstraint responses are small SDMX-ML documents; the two things
# we need are pulled out with targeted matches rather than an XML dependency.
function _parse_available(xml::AbstractString)
    obs = nothing
    m = match(r"<common:Annotation id=\"obs_count\">\s*<common:AnnotationTitle>(\d+)</common:AnnotationTitle>"s, xml)
    m === nothing || (obs = parse(Int, m[1]))
    kvs = Dict{String,Vector{String}}()
    for kv in eachmatch(r"<common:KeyValue id=\"([^\"]+)\">(.*?)</common:KeyValue>"s, xml)
        kvs[String(kv[1])] =
            String[String(v[1]) for v in eachmatch(r"<common:Value>([^<]*)</common:Value>", kv[2])]
    end
    return obs, kvs
end

function _availableconstraint(flow, dimension; agency, kwargs...)
    dims = get_dimensions(flow; agency)
    key = sdmx_key(dims; kwargs...)
    return _availableconstraint(flow, key, dimension; agency)
end

function _availableconstraint(flow, key::AbstractString, dimension; agency)
    id = get_dataflow(flow; agency).id
    url = string(ENDPOINT[], "/availableconstraint/", id, "/", key, "/all/", dimension)
    return _parse_available(_fetch(url; accept = "application/xml"))
end

"""
    available(flow, dimension; agency = "IT1", DIMS...) -> DataFrame

The codes of `dimension` that **actually have data** in `flow`, optionally
under a partial key given by uppercase dimension keywords — a ~3 KB request
against the multi-MB codelist, and the answer to "which codes exist *here*"
rather than "which exist at all".

```julia
available("115_333", "ECON_ACTIVITY_NACE_2007"; FREQ = "M", ADJUSTMENT = "Y")
```
"""
function available(flow::AbstractString, dimension::AbstractString;
                   agency::AbstractString = "IT1", kwargs...)
    dims = get_dimensions(flow; agency)
    dimension in dims ||
        throw(ArgumentError("unknown dimension $dimension; $flow has " *
                            join(dims, ", ")))
    _, kvs = _availableconstraint(flow, dimension; agency, kwargs...)
    return DataFrame(code = get(kvs, String(dimension), String[]))
end

"""
    nobs(flow; agency = "IT1", DIMS...) -> Int
    nobs(flow, key::AbstractString; agency = "IT1") -> Int

How many observations the key selected by the uppercase dimension keywords
(or the ready-made `key`) would return — **before** paying for the data
request. Sizes a query for one ~3 KB request; [`get_data`](@ref) refuses
oversized wildcard queries, and this is how you check first.

```julia
nobs("115_333"; FREQ = "M", ADJUSTMENT = "Y")
nobs("115_333", "M...Y.")
```
"""
function nobs(flow::AbstractString; agency::AbstractString = "IT1", kwargs...)
    dims = get_dimensions(flow; agency)
    return nobs(flow, sdmx_key(dims; kwargs...); agency)
end

function nobs(flow::AbstractString, key::AbstractString; agency::AbstractString = "IT1")
    dims = get_dimensions(flow; agency)
    obs, _ = _availableconstraint(flow, key, dims[1]; agency)
    obs === nothing &&
        throw(RequestFailed(200, "availableconstraint for $flow returned no obs_count"))
    return obs
end
