# Persistent response cache in a Scratch.jl scratchspace.
#
# Planned design (see CLAUDE.md): directory resolved once as
# ISTATAPI_CACHE_DIR → Preferences → @get_scratch!("istat"). Filenames are
# sha256(url * "\n" * accept) truncated to 16 hex chars plus a readable prefix
# (`+`-joined keys can exceed every filesystem's 255-byte name limit). Writes
# are atomic (`dest.part` → mv) with a `.meta.json` sidecar. Cache hits never
# touch the rate limiter.
# Public surface: cache_dir, set_cache_dir!, clear_cache!, cache_index.
