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

A message with server-side labels (`;labels=both`, headers and cells in
`"CODE: label"` form) is normalised to the plain schema: the header becomes
`CODE`, cells keep only the code, and the label part lands in a `CODE_label`
column right after it — identical to what `labels = true` produces.
"""
function read_sdmx_csv(source)
    df = CSV.read(source, DataFrame; types = String, missingstring = "",
                  pool = false)
    _split_server_labels!(df)
    idx = findfirst(==("TIME_PERIOD"), names(df))
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

# `;labels=both` turns the header "FREQ" into "FREQ: Frequency" and the cell
# "M" into "M: monthly". Undo that in place: rename the header, keep the code
# in the column, and put the labels in a `FREQ_label` column right after it —
# the same shape `_join_labels!` builds locally, so reshapers and user code
# see one schema. Columns whose cells carry no label (TIME_PERIOD, DATAFLOW)
# are only renamed.
function _split_server_labels!(df::DataFrame)
    for name in reverse(names(df))          # reverse keeps earlier indices valid
        m = match(r"^([^:\s]+): .*$"s, name)
        m === nothing && continue
        code_col = String(m[1])
        col = df[!, name]
        codes = similar(col)
        labels = fill("", length(col))
        labelled = false
        for (i, v) in enumerate(col)
            if v === missing
                codes[i] = missing
                continue
            end
            j = findfirst(": ", v)
            if j === nothing
                codes[i] = v
            else
                codes[i] = String(v[1:prevind(v, first(j))])
                labels[i] = String(v[nextind(v, last(j)):end])
                labelled = true
            end
        end
        idx = findfirst(==(name), names(df))
        df[!, idx] = codes
        rename!(df, name => code_col)
        labelled && insertcols!(df, idx + 1, Symbol(code_col, :_label) => labels)
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
