# Dataflow catalogue: shipped snapshot + zero-request lookups.
#
# Planned design (see CLAUDE.md): data/dataflows_IT1.csv ships with the
# package and is lazy-loaded into a Ref on first use — never in __init__ and
# never during precompilation. Resolution order: refreshed copy in the cache
# dir → shipped snapshot → `refresh = true` (one live request). All snapshot
# access goes through an internal _catalogue_path() so a future Artifact
# migration is mechanical.
# Public surface: get_dataflows, get_dataflow (accepts "115_333",
# "IT1,115_333,1.0" and "IT1:115_333(1.0)").
