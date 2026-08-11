# Local dataflow search over the shipped snapshot — zero requests.
#
# FredApi searches server-side (one request per query); here the catalogue is
# local, so search is free and works offline.

_norm(s::AbstractString) = Unicode.normalize(lowercase(s); stripmark = true)
_tokens(s::AbstractString) =
    String.(split(_norm(s), r"[^a-z0-9]+"; keepempty = false))

# AND semantics with prefix matching; whole-token hits beat prefix hits.
# Returns nothing when a query token matches nowhere (row excluded).
function _score(qtokens::Vector{String}, rawquery::AbstractString,
                id::AbstractString, name_en::AbstractString,
                name_it::AbstractString, lang::Symbol)
    idtoks = _tokens(id)
    entoks = lang === :it ? String[] : _tokens(name_en)
    ittoks = lang === :en ? String[] : _tokens(name_it)
    score = 0.0
    for q in qtokens
        if q in idtoks || q in entoks || q in ittoks
            score += 2.0
        elseif any(t -> startswith(t, q),
                   Iterators.flatten((idtoks, entoks, ittoks)))
            score += 1.0
        else
            return nothing
        end
    end
    # exact id match dominates
    _norm(rawquery) == _norm(id) && (score += 3.0)
    # all tokens landing whole in one language's name reads as intent
    !isempty(entoks) && all(in(entoks), qtokens) && (score += 0.5)
    !isempty(ittoks) && all(in(ittoks), qtokens) && (score += 0.5)
    # shorter names are the aggregate flows people usually want
    namelens = filter(>(0), (length(name_en), length(name_it)))
    isempty(namelens) || (score -= 0.002 * minimum(namelens))
    return score
end

"""
    search_dataflow(query; must_contain = "", lang = :both, limit = 25,
                    agency = "IT1") -> DataFrame

Rank the local dataflow catalogue against `query` — **zero requests, works
offline**. Matching is accent- and case-insensitive with AND semantics over
query tokens and prefix matching (`"industr"` finds *industriale*); ids count
too, so `"115_333"` works. `lang` restricts name matching to `:en` or `:it`
(default `:both` — ISTAT's English names are sometimes thinner than the
Italian). `must_contain` post-filters to rows whose id or names contain the
substring. Results carry a `score` column and are sorted by score descending,
then id ascending — a deterministic total order.

`query` may also be a `Regex`, matched verbatim against id and names.

# Examples
```julia
search_dataflow("industrial production")
search_dataflow("produzione industriale"; lang = :it)
search_dataflow(r"^115_")
```
"""
function search_dataflow(query::AbstractString; must_contain::AbstractString = "",
                         lang::Symbol = :both, limit::Integer = 25,
                         agency::AbstractString = "IT1")
    lang in (:en, :it, :both) ||
        throw(ArgumentError("lang must be :en, :it or :both, got :$lang"))
    qtokens = _tokens(query)
    isempty(qtokens) && throw(ArgumentError("empty query"))
    df = _catalogue("dataflows_$(agency).csv")
    hits = Int[]
    scores = Float64[]
    for (i, (id, en, it)) in enumerate(zip(df.id, df.name_en, df.name_it))
        s = _score(qtokens, query, id, en, it, lang)
        s === nothing && continue
        push!(hits, i)
        push!(scores, s)
    end
    res = df[hits, :]
    res.score = scores
    if !isempty(must_contain)
        needle = _norm(must_contain)
        keep = [occursin(needle, _norm(string(r.id, ' ', r.name_en, ' ', r.name_it)))
                for r in eachrow(res)]
        res = res[keep, :]
    end
    sort!(res, [order(:score, rev = true), :id])
    return first(res, limit)
end

function search_dataflow(query::Regex; must_contain::AbstractString = "",
                         lang::Symbol = :both, limit::Integer = 25,
                         agency::AbstractString = "IT1")
    lang in (:en, :it, :both) ||
        throw(ArgumentError("lang must be :en, :it or :both, got :$lang"))
    df = _catalogue("dataflows_$(agency).csv")
    keep = [occursin(query, r.id) ||
            (lang !== :it && occursin(query, r.name_en)) ||
            (lang !== :en && occursin(query, r.name_it)) for r in eachrow(df)]
    res = df[keep, :]
    res.score = ones(nrow(res))
    if !isempty(must_contain)
        needle = _norm(must_contain)
        filtkeep = [occursin(needle, _norm(string(r.id, ' ', r.name_en, ' ', r.name_it)))
                    for r in eachrow(res)]
        res = res[filtkeep, :]
    end
    sort!(res, :id)
    return first(res, limit)
end
