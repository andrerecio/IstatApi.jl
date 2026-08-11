# Local dataflow search over the shipped snapshot — zero requests.
#
# Ranking: normalise (lowercase + strip accents), tokenise on [^a-z0-9]+,
# AND semantics with prefix matching; whole-token hits beat prefix hits,
# +3 for an exact id match, bonus for one-language coverage, small penalty for
# name length. Deterministic order: score desc, then id asc — tests depend on
# a total order. Accepts a Regex query too; `lang = :both` by default.
# Public surface: search_dataflow.
