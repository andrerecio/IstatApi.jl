"""
    IstatError

Abstract supertype of every exception thrown by IstatApi.

Concrete subtypes: [`OfflineError`](@ref), [`BudgetExhaustedError`](@ref),
[`RateLimitError`](@ref), [`BannedError`](@ref), [`NoDataError`](@ref),
[`RequestFailed`](@ref).
"""
abstract type IstatError <: Exception end

"""
    OfflineError(what)

Thrown when offline mode is active (see [`offline!`](@ref)) and `what` — a
request the package would have made — is not available from the cache or the
shipped snapshots.
"""
struct OfflineError <: IstatError
    what::String
end

function Base.showerror(io::IO, e::OfflineError)
    print(io, "OfflineError: offline mode is active and \"", e.what,
        "\" is not cached. Call IstatApi.online!() (or unset ISTATAPI_OFFLINE) ",
        "to allow network access.")
end

"""
    BudgetExhaustedError(budget)

Thrown by `with_budget(f, n)` when the wrapped code tries to make more than `n`
network requests.
"""
struct BudgetExhaustedError <: IstatError
    budget::Int
end

function Base.showerror(io::IO, e::BudgetExhaustedError)
    print(io, "BudgetExhaustedError: the request budget of ", e.budget,
        " network request", e.budget == 1 ? "" : "s", " is exhausted.")
end

"""
    RateLimitError(retry_after)

The server answered 429 (too many requests). `retry_after` is the value of the
`Retry-After` response header in seconds, or `nothing` if absent.

ISTAT enforces 5 requests per minute per IP and blocks offenders for 1–2 days,
so a 429 also persists a ban sentinel — see [`BannedError`](@ref).
"""
struct RateLimitError <: IstatError
    retry_after::Union{Nothing,Int}
end

function Base.showerror(io::IO, e::RateLimitError)
    print(io, "RateLimitError: the server answered 429 (too many requests)")
    e.retry_after === nothing || print(io, "; Retry-After: ", e.retry_after, " s")
    print(io, ".")
end

"""
    BannedError(until)

A previous response indicated this IP is blocked by the service (ISTAT blocks
IPs that exceed 5 requests/minute for 1–2 days). The ban sentinel persists
across Julia sessions and IstatApi refuses to touch the network until `until`.

If you are confident the block has lapsed, call `IstatApi.clear_ban!()`.
"""
struct BannedError <: IstatError
    until::DateTime
end

function Base.showerror(io::IO, e::BannedError)
    print(io, "BannedError: a previous response indicated this IP is blocked ",
        "by the service; refusing to touch the network until ", e.until,
        " (continuing to send requests extends the block). ",
        "If you are confident the block has lapsed, call IstatApi.clear_ban!().")
end

"""
    NoDataError(url)

The request was well-formed but selected no observations — the commonest user
mistake is a key built from a code that exists in the codelist but has no data
in this dataflow. Use `available(flow, dimension)` to list the codes that
actually have data.
"""
struct NoDataError <: IstatError
    url::String
end

function Base.showerror(io::IO, e::NoDataError)
    print(io, "NoDataError: the key is syntactically valid but selects no data (",
        e.url, "). A code can exist in a codelist yet have no observations in ",
        "this dataflow — use available(flow, dimension) to list codes that do.")
end

"""
    RequestFailed(status, url)

The server answered with an unexpected HTTP status not covered by a more
specific exception.
"""
struct RequestFailed <: IstatError
    status::Int
    url::String
end

function Base.showerror(io::IO, e::RequestFailed)
    print(io, "RequestFailed: HTTP ", e.status, " for ", e.url)
end
