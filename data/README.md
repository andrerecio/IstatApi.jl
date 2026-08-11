# Shipped catalogue snapshots

This directory will hold trimmed snapshots of ISTAT's structural catalogue:

- `dataflows_IT1.csv` — id, agency, version, name_en, name_it, dsd,
  last_update, metadata_url for all dataflows (from `/dataflow/IT1`).
- `datastructures_IT1.csv` — dsd, position, dimension, codelist for every DSD
  (from `/datastructure/IT1`).
- `*.meta.toml` — snapshot date and row counts.

They make discovery, search and key construction work **offline, with zero
requests**. They are produced by `dev/refresh_catalogue.jl`, which is
`--yes`-gated and runs under the live throttle (ISTAT allows 5 requests per
minute per IP). Never fetch the catalogue any other way.
