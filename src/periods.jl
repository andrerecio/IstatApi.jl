# SDMX TIME_PERIOD parsing.
#
# Not exported — `parse_period` is too generic a name for a user namespace;
# call it as IstatApi.parse_period.

"""
    parse_period(s; at = :start) -> Date

Parse an SDMX `TIME_PERIOD` string into a `Date`. Handled shapes: `"2026"`,
`"2026-S1"`, `"2026-Q2"`, `"2026-06"`, `"2026-06-15"`.

`at = :start` (the default) returns the period's first day — the ISO/Eurostat
convention, which never invents a date inside the period. `at = :last` returns
the period's last day; a "third month of the quarter" convention is then
`Dates.firstdayofmonth(parse_period(s; at = :last))`.

The frequency the `Date` no longer carries is available from
[`IstatApi.period_frequency`](@ref) and travels alongside data as the `freq`
column.

# Examples
```jldoctest
julia> IstatApi.parse_period("2026-Q2")
2026-04-01

julia> IstatApi.parse_period("2026-Q2", at = :last)
2026-06-30

julia> IstatApi.parse_period("2026")
2026-01-01
```
"""
function parse_period(s::AbstractString; at::Symbol = :start)
    at in (:start, :last) ||
        throw(ArgumentError("at must be :start or :last, got :$at"))
    str = strip(s)
    last_ = at === :last

    m = match(r"^(\d{4})$", str)
    if m !== nothing
        y = parse(Int, m[1])
        return last_ ? Date(y, 12, 31) : Date(y, 1, 1)
    end
    m = match(r"^(\d{4})-S([12])$", str)
    if m !== nothing
        y, half = parse(Int, m[1]), parse(Int, m[2])
        return last_ ? lastdayofmonth(Date(y, 6half, 1)) : Date(y, 6half - 5, 1)
    end
    m = match(r"^(\d{4})-Q([1-4])$", str)
    if m !== nothing
        y, q = parse(Int, m[1]), parse(Int, m[2])
        return last_ ? lastdayofmonth(Date(y, 3q, 1)) : Date(y, 3q - 2, 1)
    end
    m = match(r"^(\d{4})-(\d{2})$", str)
    if m !== nothing
        y, mo = parse(Int, m[1]), parse(Int, m[2])
        1 <= mo <= 12 ||
            throw(ArgumentError("invalid TIME_PERIOD \"$s\": month out of range"))
        return last_ ? lastdayofmonth(Date(y, mo, 1)) : Date(y, mo, 1)
    end
    m = match(r"^(\d{4})-(\d{2})-(\d{2})$", str)
    if m !== nothing
        return Date(parse(Int, m[1]), parse(Int, m[2]), parse(Int, m[3]))
    end
    throw(ArgumentError("unrecognised SDMX TIME_PERIOD \"$s\" " *
                        "(expected e.g. 2026, 2026-S1, 2026-Q2, 2026-06 or 2026-06-15)"))
end

"""
    period_frequency(s) -> String

The frequency letter of an SDMX `TIME_PERIOD` string: `"A"` (annual), `"S"`
(half-yearly), `"Q"` (quarterly), `"M"` (monthly) or `"D"` (daily) — matching
ISTAT's `FREQ` dimension codes.

# Examples
```jldoctest
julia> IstatApi.period_frequency("2026-Q2")
"Q"
```
"""
function period_frequency(s::AbstractString)
    str = strip(s)
    occursin(r"^\d{4}$", str) && return "A"
    occursin(r"^\d{4}-S[12]$", str) && return "S"
    occursin(r"^\d{4}-Q[1-4]$", str) && return "Q"
    occursin(r"^\d{4}-\d{2}$", str) && return "M"
    occursin(r"^\d{4}-\d{2}-\d{2}$", str) && return "D"
    throw(ArgumentError("unrecognised SDMX TIME_PERIOD \"$s\""))
end
