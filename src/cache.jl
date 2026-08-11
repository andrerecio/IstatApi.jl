# Persistent response cache in a Scratch.jl scratchspace.
#
# Filenames are a readable prefix plus 16 hex chars of
# sha256(url * "\n" * accept): a `+`-joined SDMX key can push a URL past every
# filesystem's 255-byte name limit, so the URL itself can never be the name.
# Writes are atomic (`dest.part` → mv) with a `.meta.json` sidecar. Cache hits
# never touch the rate limiter (see transport.jl).

const _CACHE_DIR = Ref{String}("")

# Files in the cache dir that are not cached responses and must survive
# clear_cache!.
const _CACHE_INTERNAL = ("requests.log", "requests.lock", "banned_until")

_is_internal(name::AbstractString) =
    name in _CACHE_INTERNAL || endswith(name, ".part")

# Resolution order: ISTATAPI_CACHE_DIR → the `cache_dir` preference → a
# Scratch.jl scratchspace. Resolved lazily on first use — never at load or
# precompile time.
function _resolve_cache_dir()
    dir = get(ENV, "ISTATAPI_CACHE_DIR", "")
    isempty(dir) || return abspath(dir)
    pref = load_preference(IstatApi, "cache_dir", nothing)
    pref === nothing || return abspath(pref)
    return @get_scratch!("istat")
end

"""
    cache_dir() -> String

The directory holding cached responses, the cross-process request log and the
ban sentinel (created if necessary). Resolution order: the `ISTATAPI_CACHE_DIR`
environment variable, the `cache_dir` preference (see [`set_cache_dir!`](@ref)),
a Scratch.jl scratchspace managed by Pkg.
"""
function cache_dir()
    isempty(_CACHE_DIR[]) && (_CACHE_DIR[] = _resolve_cache_dir())
    mkpath(_CACHE_DIR[])
    return _CACHE_DIR[]
end

"""
    set_cache_dir!(path; persist = false)

Use `path` for the cache from now on. With `persist = true` the choice is saved
as a preference in `LocalPreferences.toml` and survives restarts.
"""
function set_cache_dir!(path::AbstractString; persist::Bool = false)
    _CACHE_DIR[] = abspath(path)
    mkpath(_CACHE_DIR[])
    persist && set_preferences!(IstatApi, "cache_dir" => _CACHE_DIR[])
    return _CACHE_DIR[]
end

"""
    clear_cache!(; older_than = nothing) -> Int

Delete cached responses and their metadata sidecars, returning the number of
files removed. The request log and the ban sentinel are never touched. With
`older_than` a `Dates.Period`, only files modified longer ago are removed.
"""
function clear_cache!(; older_than::Union{Nothing,Period} = nothing)
    dir = cache_dir()
    cutoff = older_than === nothing ? nothing : now(UTC) - older_than
    removed = 0
    for name in readdir(dir)
        _is_internal(name) && continue
        path = joinpath(dir, name)
        isfile(path) || continue
        if cutoff !== nothing
            Dates.unix2datetime(mtime(path)) < cutoff || continue
        end
        rm(path; force = true)
        removed += 1
    end
    return removed
end

"""
    cache_index() -> DataFrame

One row per cached response: `file`, `url`, `accept`, `status`, `bytes`,
`fetched_at`.
"""
function cache_index()
    dir = cache_dir()
    df = DataFrame(file = String[], url = String[], accept = String[],
                   status = Int[], bytes = Int[], fetched_at = String[])
    for name in sort(readdir(dir))
        endswith(name, ".meta.json") || continue
        meta = JSON3.read(read(joinpath(dir, name), String))
        push!(df, (file = String(chopsuffix(name, ".meta.json")),
                   url = String(get(meta, :url, "")),
                   accept = String(get(meta, :accept, "")),
                   status = Int(get(meta, :status, 0)),
                   bytes = Int(get(meta, :bytes, 0)),
                   fetched_at = String(get(meta, :fetched_at, ""))))
    end
    return df
end

function _cache_path(url::AbstractString, accept::AbstractString)
    h = bytes2hex(sha256(codeunits(string(url, '\n', accept))))[1:16]
    stem = replace(String(url), r"^https?://" => "")
    stem = replace(stem, r"[^A-Za-z0-9._-]" => "_")
    return joinpath(cache_dir(), string(first(stem, 40), '-', h))
end

function _cache_read(url::AbstractString, accept::AbstractString)
    path = _cache_path(url, accept)
    isfile(path) || return nothing
    return read(path, String)
end

function _cache_write(url::AbstractString, accept::AbstractString,
                      status::Integer, body)
    path = _cache_path(url, accept)
    tmp = path * ".part"
    write(tmp, body)
    mv(tmp, path; force = true)
    meta = (url = String(url), accept = String(accept), status = Int(status),
            bytes = sizeof(body), fetched_at = string(now(UTC)))
    metatmp = path * ".meta.json.part"
    write(metatmp, JSON3.write(meta))
    mv(metatmp, path * ".meta.json"; force = true)
    return path
end
