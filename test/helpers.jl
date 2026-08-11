# Shared test helpers.
#
# The fixture transport is layer 2 of the offline guarantee: it replaces
# IstatApi._TRANSPORT[] so the full request path — URL construction, gates,
# status handling, parsing, caching — runs end to end with zero network, while
# recording every URL it is asked for so tests can assert exact request counts.

function with_transport(f, transport)
    old = IstatApi._TRANSPORT[]
    IstatApi._TRANSPORT[] = transport
    try
        return f()
    finally
        IstatApi._TRANSPORT[] = old
    end
end

function with_online(f)
    online!()
    try
        return f()
    finally
        offline!()
    end
end

function with_fast_limit(f; interval = 0.0, per_minute = 10_000)
    set_rate_limit!(; interval, per_minute)
    try
        return f()
    finally
        set_rate_limit!()
    end
end

# Drop refreshed catalogue copies (files + in-memory cache) so later testsets
# see the shipped snapshot again.
function reset_catalogue!()
    for f in readdir(cache_dir())
        if startswith(f, "dataflows_") || startswith(f, "datastructures_")
            rm(joinpath(cache_dir(), f); force = true)
        end
    end
    empty!(IstatApi._CATALOGUE_CACHE)
    return
end

# responses :: url => (status, headers, body); every requested URL is pushed
# onto `log`.
function recording_transport(responses::AbstractDict; log::Vector{String} = String[])
    return function (url, accept)
        push!(log, String(url))
        haskey(responses, url) ||
            error("fixture transport: no fixture for $url (accept: $accept)")
        return responses[url]
    end
end
