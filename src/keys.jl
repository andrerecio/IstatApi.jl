# SDMX key and URL construction — pure string algebra, zero requests.
#
# A key is `.`-separated, one position per dimension in DSD order; empty
# position = wildcard, `+` within a position = OR (one request, many series).
# The dimension count comes from the DSD — never inferred from a URL that
# happens to work (the server tolerates a spurious trailing dot).

# Codes are strings by decree: an Int here would silently corrupt zero-padded
# codes ("0020" → 20), the single most damaging user mistake.
function _key_code(dim::AbstractString, v)::String
    if v isa AbstractString || v isa Symbol || v isa AbstractChar
        code = string(v)
        isempty(code) &&
            throw(ArgumentError("empty code for dimension $dim — omit the keyword to wildcard it"))
        occursin(r"[.+/\s]", code) &&
            throw(ArgumentError("invalid code \"$code\" for dimension $dim: " *
                                "codes cannot contain '.', '+', '/' or spaces"))
        return code
    end
    throw(ArgumentError("SDMX codes are strings; got $dim = $v (a $(typeof(v))). " *
                        "Zero-padded codes like \"0020\" would be corrupted — " *
                        "pass the code as a string."))
end

function _key_position(dim::AbstractString, v)::String
    if v isa AbstractVector || v isa Tuple
        isempty(v) &&
            throw(ArgumentError("empty code list for dimension $dim — omit the keyword to wildcard it"))
        return join((_key_code(dim, x) for x in v), '+')
    end
    return _key_code(dim, v)
end

"""
    sdmx_key(dimensions; DIMS...) -> String

Build an SDMX data key for the ordered dimension list `dimensions` (DSD
order). Uppercase keywords name dimensions; a scalar selects one code, a
vector `+`-joins codes into an OR (one request returning many series — never
loop over codes), and an omitted dimension is a wildcard. An unknown keyword
throws `ArgumentError` locally instead of wasting one of ISTAT's five requests
per minute.

# Examples
```jldoctest
julia> sdmx_key(["FREQ", "REF_AREA", "DATA_TYPE", "ADJUSTMENT", "ECON_ACTIVITY_NACE_2007"];
                FREQ = "M", ADJUSTMENT = "Y", ECON_ACTIVITY_NACE_2007 = ["0020", "0040", "C"])
"M...Y.0020+0040+C"

julia> sdmx_key(["FREQ", "REF_AREA"])
"."
```
"""
function sdmx_key(dimensions::AbstractVector{<:AbstractString}; kwargs...)
    isempty(dimensions) && throw(ArgumentError("empty dimension list"))
    selected = Dict{String,String}()
    for (k, v) in kwargs
        dim = String(k)
        dim in dimensions ||
            throw(ArgumentError("unknown dimension $dim; this key has " *
                                join(dimensions, ", ")))
        selected[dim] = _key_position(dim, v)
    end
    return join((get(selected, d, "") for d in dimensions), '.')
end

# Normalise the three accepted dataflow spellings to the URL form
# "AGENCY,ID[,VERSION]". "IT1:115_333(1.0)" is what the CSV's DATAFLOW column
# contains, so results round-trip. The version is deliberately optional: the
# server resolves the latest, and a shipped snapshot's version can go stale
# harmlessly.
function _flow_ref(flow::AbstractString; agency::AbstractString = "IT1")
    occursin(',', flow) && return String(flow)
    m = match(r"^([A-Za-z0-9_]+):([A-Za-z0-9_.]+)\((.+)\)$", flow)
    m === nothing || return string(m[1], ',', m[2], ',', m[3])
    return string(agency, ',', flow)
end

"""
    sdmx_url(flow, key; from = nothing, to = nothing, agency = "IT1") -> String

The data URL for `flow` and `key`. `flow` may be a bare id (`"115_333"`), the
explicit `"IT1,115_333,1.0"` form, or the `"IT1:115_333(1.0)"` form found in
the `DATAFLOW` column of results. `from`/`to` become `startPeriod`/`endPeriod`
(note: ISTAT's `endPeriod` is known to return up to one extra year — trim
after parsing if the boundary matters).

# Examples
```jldoctest
julia> sdmx_url("115_333", "M...Y.", from = "2020")
"https://esploradati.istat.it/SDMXWS/rest/data/IT1,115_333/M...Y.?startPeriod=2020"
```
"""
function sdmx_url(flow::AbstractString, key::AbstractString;
                  from = nothing, to = nothing, agency::AbstractString = "IT1")
    url = string(ENDPOINT[], "/data/", _flow_ref(flow; agency), "/", key)
    params = String[]
    from === nothing || push!(params, "startPeriod=" * string(from))
    to === nothing || push!(params, "endPeriod=" * string(to))
    isempty(params) || (url *= "?" * join(params, "&"))
    return url
end
