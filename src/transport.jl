# Network funnel — the single point where IstatApi touches the network.
#
# `_TRANSPORT[]` holds a swappable `(url, accept) -> (status, headers, body)`
# function; tests replace it with a fixture transport, which is what makes the
# offline test guarantee structural rather than aspirational. The real
# implementation wraps exactly one HTTP.get call.

_user_agent() = string("IstatApi.jl/", pkgversion(@__MODULE__))

function _http_get(url::AbstractString, accept::AbstractString)
    resp = HTTP.get(url;
        headers = ["Accept" => accept,
                   # gzip is not reliably honoured by the server; a bonus, not
                   # a promise
                   "Accept-Encoding" => "gzip",
                   "User-Agent" => _user_agent()],
        # 404/429/403 must arrive as data, not exceptions — they carry
        # different consequences (NoDataError vs ban sentinel).
        status_exception = false,
        # Load-bearing: HTTP.jl retries idempotent requests by default, and a
        # silent 4× retry under ISTAT's 5 requests/minute limit is a
        # self-inflicted IP ban.
        retry = false,
        connect_timeout = 15,
        readtimeout = 120,
        # nothing = decompress only when the response says Content-Encoding:
        # gzip; `true` would force-gunzip plain bodies and crash — the server
        # does not reliably compress.
        decompress = nothing)
    return (resp.status, resp.headers, resp.body)
end

const _TRANSPORT = Ref{Any}(_http_get)

function _retry_after(headers)
    for (k, v) in headers
        lowercase(String(k)) == "retry-after" && return tryparse(Int, strip(String(v)))
    end
    return nothing
end

_as_string(body) = body isa AbstractString ? String(body) : String(copy(body))

# The one road to the network. Order matters: cache hits return before any
# gate; offline mode and the ban sentinel are checked before the budget is
# spent; the throttle runs last, immediately before the request.
function _fetch(url::AbstractString;
                accept::AbstractString = "application/json",
                cache::Bool = true, force::Bool = false)
    if cache && !force
        hit = _cache_read(url, accept)
        hit === nothing || return hit
    end
    isoffline() && throw(OfflineError(url))
    _check_ban!()
    _spend_budget!()
    _throttle!()
    status, headers, body = _TRANSPORT[](url, accept)
    _REQUEST_COUNT[] += 1
    if status == 200
        isempty(body) && throw(NoDataError(url))
        cache && _cache_write(url, accept, status, body)
        return _as_string(body)
    elseif status == 404 || status == 204
        throw(NoDataError(url))
    elseif status == 429
        retry_after = _retry_after(headers)
        _set_ban!(retry_after === nothing ? Hour(24) : Second(retry_after))
        throw(RateLimitError(retry_after))
    elseif status == 403
        # Ambiguous: ISTAT 403s both banned IPs and malformed URLs. One hour,
        # not a day — locking a user out for 24 h over a typo is unacceptable.
        _set_ban!(Hour(1))
        throw(RequestFailed(status, url))
    else
        throw(RequestFailed(status, url))
    end
end
