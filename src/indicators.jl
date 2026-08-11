# Curated shortcuts — hand-maintained mappings that go stale when ISTAT
# revises a dataflow, so each names its dataflow in the docstring (drop to
# get_data if one drifts) and has an opt-in check in test/live_tests.jl.

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
