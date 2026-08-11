# SDMX-CSV parsing (Accept: application/vnd.sdmx.data+csv;version=1.0.0).
#
# Layout: DATAFLOW, <dimensions...>, TIME_PERIOD, OBS_VALUE, then status/note
# columns (OBS_STATUS, NOTE_*, BASE_PER, UNIT_MEAS, UNIT_MULT). NOTE_* fields
# are free text with quoted commas, so everything goes through CSV.jl — never
# a naive splitter.

"""
    read_sdmx_csv(source) -> DataFrame

Parse an SDMX-CSV data message from a file path, an `IO`, raw bytes, or a
string containing the CSV itself.

Every column is read as `String` — SDMX codes must stay strings (`"0020"` is
not the number 20) — except `OBS_VALUE`, which becomes
`Union{Float64, Missing}` with `missing` for empty values. Two columns are
added after `TIME_PERIOD`: `period::Date`, the period's start (see
[`IstatApi.parse_period`](@ref)), and `freq::String`, its frequency letter.
"""
function read_sdmx_csv(source)
    df = CSV.read(source, DataFrame; types = String, missingstring = "",
                  pool = false)
    # server-side labels (`;labels=both`) relabel the headers too:
    # "TIME_PERIOD" becomes "TIME_PERIOD: Time"
    idx = findfirst(n -> n == "TIME_PERIOD" || startswith(n, "TIME_PERIOD:"),
                    names(df))
    idx === nothing &&
        throw(ArgumentError("not an SDMX-CSV data message: no TIME_PERIOD column"))
    tp = df[!, idx]
    any(ismissing, tp) &&
        throw(ArgumentError("malformed SDMX-CSV: empty TIME_PERIOD values"))
    insertcols!(df, idx + 1,
        :period => parse_period.(tp),
        :freq => period_frequency.(tp))
    if "OBS_VALUE" in names(df)
        df.OBS_VALUE = Union{Float64,Missing}[
            v === missing ? missing : parse(Float64, v) for v in df.OBS_VALUE]
    end
    return df
end

# A string argument is a path if such a file exists, otherwise the CSV content
# itself (fetched bodies arrive as strings). isfile can throw ENAMETOOLONG on
# content-sized strings, so it is only consulted for path-plausible ones.
function read_sdmx_csv(s::AbstractString)
    ispath = !occursin('\n', s) && length(s) < 4096 && isfile(s)
    return invoke(read_sdmx_csv, Tuple{Any}, ispath ? String(s) : IOBuffer(s))
end
