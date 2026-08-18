# Curated shortcuts — hand-maintained mappings that go stale when ISTAT
# revises a dataflow, so each names its dataflow in the docstring (drop to
# get_data if one drifts) and has an opt-in check in test/live_tests.jl.
# Codes verified live 2026-08-11.

"""
    industrial_production(; adjustment = "Y", codes = ["0020"],
                          from = nothing, to = nothing, kwargs...) -> DataFrame

Monthly industrial production index for Italy — dataflow **115_333**
(`FREQ = "M"`, `REF_AREA = "IT"`, `DATA_TYPE = "IND_PROD_21"`, base 2021=100).
`adjustment` is a `CL_CORREZ` code (`"Y"` seasonally adjusted, `"N"` raw);
`codes` are `CL_ATECO_2007` activities (`"0020"` is total industry excluding
construction). Remaining keywords pass through to [`get_data`](@ref).
"""
industrial_production(; adjustment = "Y", codes = ["0020"],
                      from = nothing, to = nothing, kwargs...) =
    get_data("115_333"; FREQ = "M", REF_AREA = "IT", DATA_TYPE = "IND_PROD_21",
             ADJUSTMENT = String(adjustment), ECON_ACTIVITY_NACE_2007 = codes,
             from, to, kwargs...)

# ISTAT vintage codes: "2024M10", "2025M4_1", "2026M7G30". Unparseable codes
# sort first, so a recognised vintage always beats them.
function _edition_key(s::AbstractString)
    m = match(r"^(\d{4})M(\d{1,2})(?:G(\d{1,2}))?(?:_(\d+))?$", s)
    m === nothing && return (0, 0, 0, 0)
    part(i) = m[i] === nothing ? 0 : parse(Int, m[i])
    return (part(1), part(2), part(3), part(4))
end

# Resolve edition = :latest to the newest vintage that has data under the
# given key — one ~3 KB availableconstraint request (cached thereafter). Only
# uppercase keywords (dimensions) take part; lowercase get_data options are
# ignored here.
function _resolve_edition(flow, edition; kwargs...)
    edition === :latest || return String(edition)
    dims = (; (k => v for (k, v) in kwargs if _is_dimension_kw(k))...)
    codes = available(flow, "EDITION"; dims...).code
    isempty(codes) &&
        throw(NoDataError("no EDITION has data for this $flow selection"))
    return codes[argmax(_edition_key.(codes))]
end

_is_dimension_kw(k::Symbol) = (s = String(k); s == uppercase(s))

"""
    gdp(; valuation = "L_2020", adjustment = "Y", edition = :latest,
        from = nothing, to = nothing, kwargs...) -> DataFrame

Quarterly Italian GDP at market prices — dataflow **163_156**
(`FREQ = "Q"`, `REF_AREA = "IT"`, `DATA_TYPE_AGGR = "B1GQ_B_W2_S1"`).
`valuation`: `"L_2020"` chain-linked (reference year 2020), `"V"` current
prices, `"Y"`/`"G1"`/`"G4"` per `CL_VAL`. The flow is versioned by a vintage
dimension: `edition = :latest` resolves the newest vintage with one ~3 KB
request (cached); pass a code like `"2026M5"` to pin one.
"""
function gdp(; valuation = "L_2020", adjustment = "Y", edition = :latest,
             from = nothing, to = nothing, kwargs...)
    fixed = (FREQ = "Q", REF_AREA = "IT", DATA_TYPE_AGGR = "B1GQ_B_W2_S1",
             VALUATION = String(valuation), ADJUSTMENT = String(adjustment))
    ed = _resolve_edition("163_156", edition; fixed..., kwargs...)
    return get_data("163_156"; fixed..., EDITION = ed, from, to, kwargs...)
end

"""
    consumer_prices(; coicop = "00", measure = "4",
                    from = nothing, to = nothing, kwargs...) -> DataFrame

Monthly NIC consumer price index for the whole nation, base 2025=100 —
dataflow **167_745**, data from 2026 onwards (`FREQ = "M"`,
`REF_AREA = "IT"`, `DATA_TYPE = "85"`). `measure`: `"4"` index number, `"6"`
% change on previous period, `"7"` % change on the same period of the
previous year. `coicop` is an `ECOICOP_2` code (`"00"` all items; see
`get_codelist("167_745", "ECOICOP_2")`). For 2016–2025 history use the
predecessor flow: `get_data("167_744"; ...)` (base 2015=100).
"""
consumer_prices(; coicop = "00", measure = "4",
                from = nothing, to = nothing, kwargs...) =
    get_data("167_745"; FREQ = "M", REF_AREA = "IT", DATA_TYPE = "85",
             MEASURE = String(measure), ECOICOP_2 = coicop,
             from, to, kwargs...)

"""
    unemployment(; age = "Y15-74", sex = "9", adjustment = "Y",
                 edition = :latest, from = nothing, to = nothing, kwargs...) -> DataFrame

Monthly Italian unemployment rate — dataflow **151_874** (`FREQ = "M"`,
`REF_AREA = "IT"`, `DATA_TYPE = "UNEM_R"`). `age` bands include `"Y15-74"`
(the headline rate), `"Y15-24"`, `"Y25-34"`, …; `sex`: `"9"` total, `"1"`
males, `"2"` females; `adjustment`: `"Y"` seasonally adjusted, `"N"` raw.
Vintage-versioned like [`gdp`](@ref): `edition = :latest` (one ~3 KB request)
or a pinned code.
"""
function unemployment(; age = "Y15-74", sex = "9", adjustment = "Y",
                      edition = :latest, from = nothing, to = nothing, kwargs...)
    fixed = (FREQ = "M", REF_AREA = "IT", DATA_TYPE = "UNEM_R",
             ADJUSTMENT = String(adjustment), SEX = String(sex),
             AGE = String(age))
    ed = _resolve_edition("151_874", edition; fixed..., kwargs...)
    return get_data("151_874"; fixed..., EDITION = ed, from, to, kwargs...)
end
