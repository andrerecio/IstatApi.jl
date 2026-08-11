# Data structures (DSDs): dimension lists from the shipped snapshot.
#
# Still to come here (see CLAUDE.md): `DataStructure` with cached codelists
# and a show method printing the key template; get_datastructure/get_codelist
# (one request via ?references=children); available/nobs wrapping
# /availableconstraint.

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
