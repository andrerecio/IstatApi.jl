# Cross-process rate limiter, request budget and ban sentinel.
#
# ISTAT's limit (5 requests/minute, exceeding it blocks the IP for 1–2 days)
# is per IP, so the limiter must be per machine, not per process: state lives
# in `<cache>/requests.log` guarded by FileWatching.Pidfile.mkpidlock, plus an
# in-process ReentrantLock. Two gates: a minimum interval between requests and
# a cap per rolling 60 s window. Cache hits never reach this file.

const _RATE_LOCK = ReentrantLock()
const _RATE = Ref{@NamedTuple{interval::Float64, per_minute::Int}}((interval = 15.0, per_minute = 4))
const _REQUEST_COUNT = Ref{Int}(0)
const _BUDGET = Ref{Union{Nothing,Tuple{Int,Int}}}(nothing)   # (remaining, total)

"""
    set_rate_limit!(; interval = 15.0, per_minute = 4)

Configure the two throttle gates: the minimum seconds between requests and the
maximum requests per rolling 60 s window. The defaults leave a margin under
ISTAT's published limit (5 requests/minute, i.e. one every 12 s) for clock skew
and for the server counting differently — loosen them at your own risk: the
penalty for exceeding the limit is an IP block of 1–2 days.
"""
function set_rate_limit!(; interval::Real = 15.0, per_minute::Integer = 4)
    interval >= 0 || throw(ArgumentError("interval must be ≥ 0, got $interval"))
    per_minute >= 1 || throw(ArgumentError("per_minute must be ≥ 1, got $per_minute"))
    _RATE[] = (interval = Float64(interval), per_minute = Int(per_minute))
    return _RATE[]
end

"""
    rate_limit() -> (interval = ..., per_minute = ...)

The current throttle settings. See [`set_rate_limit!`](@ref).
"""
rate_limit() = _RATE[]

"""
    requests_used() -> Int

How many network requests this session has actually sent (cache hits do not
count).
"""
requests_used() = _REQUEST_COUNT[]

"""
    with_budget(f, n)

Run `f()` allowing at most `n` network requests; one more throws
[`BudgetExhaustedError`](@ref) before touching the network. Cache hits are
free. Useful to make a script's request cost explicit:

```julia
with_budget(2) do
    get_data("115_333"; FREQ = "M")
end
```
"""
function with_budget(f, n::Integer)
    n >= 0 || throw(ArgumentError("budget must be ≥ 0, got $n"))
    old = _BUDGET[]
    _BUDGET[] = (Int(n), Int(n))
    try
        return f()
    finally
        _BUDGET[] = old
    end
end

function _spend_budget!()
    b = _BUDGET[]
    b === nothing && return
    remaining, total = b
    remaining <= 0 && throw(BudgetExhaustedError(total))
    _BUDGET[] = (remaining - 1, total)
    return
end

# --- throttle ---------------------------------------------------------------

# Pure so the rolling-window logic is testable without sleeping: given the
# recorded stamps, the rate settings and the current time, how long must the
# next request wait?
function _wait_time(stamps::Vector{Float64},
                    rate::NamedTuple, t::Float64)
    w = 0.0
    isempty(stamps) || (w = max(w, last(stamps) + rate.interval - t))
    recent = filter(s -> t - s < 60.0, stamps)
    if length(recent) >= rate.per_minute
        # the oldest of the newest `per_minute` stamps must age out first
        kth = sort(recent; rev = true)[rate.per_minute]
        w = max(w, kth + 60.0 - t)
    end
    return w
end

function _read_stamps(logfile::AbstractString)
    isfile(logfile) || return Float64[]
    stamps = Float64[]
    for line in eachline(logfile)
        s = tryparse(Float64, strip(line))
        s === nothing || push!(stamps, s)
    end
    return stamps
end

function _append_stamp(logfile::AbstractString, t::Float64, stamps::Vector{Float64})
    keep = vcat(stamps, t)
    length(keep) > 32 && (keep = keep[end-31:end])
    tmp = logfile * ".part"
    open(tmp, "w") do io
        for s in keep
            println(io, s)
        end
    end
    mv(tmp, logfile; force = true)
    return
end

# Block until a request is allowed, then record it. The pidlock is only held
# while reading/writing the log — never while sleeping — so concurrent
# processes contend briefly and then wait on their own clocks.
function _throttle!()
    rate = _RATE[]
    logfile = joinpath(cache_dir(), "requests.log")
    lockfile = joinpath(cache_dir(), "requests.lock")
    lock(_RATE_LOCK)
    try
        while true
            w = Pidfile.mkpidlock(lockfile; stale_age = 60) do
                stamps = _read_stamps(logfile)
                w = _wait_time(stamps, rate, time())
                w <= 0 && _append_stamp(logfile, time(), stamps)
                w
            end
            w <= 0 && return
            sleep(w)
        end
    finally
        unlock(_RATE_LOCK)
    end
end

# --- ban sentinel -----------------------------------------------------------

_ban_file() = joinpath(cache_dir(), "banned_until")

# Throws BannedError without touching the network if a previous 429/403 left a
# live sentinel; silently removes an expired or unreadable one.
function _check_ban!()
    file = _ban_file()
    isfile(file) || return
    until = tryparse(DateTime, strip(read(file, String)))
    if until === nothing
        rm(file; force = true)
    elseif now(UTC) < until
        throw(BannedError(until))
    else
        rm(file; force = true)
    end
    return
end

function _set_ban!(duration::Period)
    until = now(UTC) + duration
    file = _ban_file()
    tmp = file * ".part"
    write(tmp, string(until))
    mv(tmp, file; force = true)
    return until
end

"""
    clear_ban!()

Remove the persisted ban sentinel. IstatApi writes it after a 429 (for
`Retry-After`, else 24 h) or an ambiguous 403 (1 h) and refuses to touch the
network while it is live, because sending requests to a service that has
blocked you extends the block. Call this only if you are confident the block
has lapsed — e.g. your IP changed, or the sentinel came from a malformed URL's
403.
"""
clear_ban!() = (rm(_ban_file(); force = true); nothing)
