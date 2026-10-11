# Reshaping get_data results.

# The dimension columns of a get_data result: everything between DATAFLOW and
# TIME_PERIOD except the `<DIM>_label` columns. Shared with the DuckDB
# extension, whose upsert key is DATAFLOW + these + TIME_PERIOD.
function _dimension_columns(df::AbstractDataFrame)
    tp = findfirst(==("TIME_PERIOD"), names(df))
    tp === nothing && throw(ArgumentError("expected a get_data result (no TIME_PERIOD column)"))
    return filter(c -> !endswith(c, "_label"), names(df)[2:tp-1])
end

"""
    to_wide(df; by = :auto) -> DataFrame

Reshape a [`get_data`](@ref) result to one `period` column plus one column per
series, named by `.`-joining the codes of every dimension that varies (`by`
selects the dimension columns explicitly). Errors if more than one `freq` is
present — a silently ragged wide table is a bug factory; filter to one
frequency first.

# Examples
```jldoctest
julia> df = read_sdmx_csv(\"\"\"
       DATAFLOW,FREQ,REF_AREA,TIME_PERIOD,OBS_VALUE
       IT1:X(1.0),M,IT,2026-01,1.0
       IT1:X(1.0),M,IT,2026-02,2.0
       IT1:X(1.0),M,ITC,2026-01,3.0
       IT1:X(1.0),M,ITC,2026-02,
       \"\"\");

julia> to_wide(df)
2×3 DataFrame
 Row │ period      IT        ITC
     │ Date        Float64?  Float64?
─────┼─────────────────────────────────
   1 │ 2026-01-01       1.0        3.0
   2 │ 2026-02-01       2.0  missing
```
"""
function to_wide(df::AbstractDataFrame; by = :auto)
    issubset(["TIME_PERIOD", "period", "freq", "OBS_VALUE"], names(df)) ||
        throw(ArgumentError("expected a get_data result (TIME_PERIOD/period/freq/OBS_VALUE columns)"))
    freqs = unique(df.freq)
    length(freqs) <= 1 ||
        throw(ArgumentError("more than one frequency present ($(join(freqs, ", "))) " *
                            "— reshaping would silently misalign periods; filter to one freq first"))
    dimcols = if by === :auto
        _dimension_columns(df)
    else
        String.(collect(by))
    end
    foreach(c -> c in names(df) ||
                 throw(ArgumentError("unknown dimension column $c")), dimcols)
    varying = filter(c -> length(unique(df[!, c])) > 1, dimcols)
    series = if isempty(varying)
        constname = isempty(dimcols) ? "OBS_VALUE" :
                    join((df[1, c] for c in dimcols), '.')
        fill(constname, nrow(df))
    else
        [join((r[c] for c in varying), '.') for r in eachrow(df)]
    end
    long = DataFrame(period = df.period, series = series, value = df.OBS_VALUE)
    wide = unstack(long, :period, :series, :value)
    sort!(wide, :period)
    return wide
end

"""
    to_timearray(df; by = :auto) -> TimeArray

[`to_wide`](@ref), then a `TimeArray` indexed by `period`. Requires
TimeSeries.jl (a package extension): run `using TimeSeries` first. Same
single-frequency rule as `to_wide`.
"""
to_timearray(df; by = :auto) =
    error("to_timearray requires TimeSeries.jl — run `using TimeSeries` first")
