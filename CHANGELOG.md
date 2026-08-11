# Changelog

All notable changes to this project are documented in this file, following
[Keep a Changelog](https://keepachangelog.com) and
[semantic versioning](https://semver.org).

## [0.1.0] — unreleased

Initial release.

- Discovery over shipped catalogue snapshots (4,896 dataflows, 892 DSDs),
  zero requests: `get_dataflows`, `get_dataflow`, `search_dataflow`,
  `get_dimensions`, `sdmx_key`, `sdmx_url`.
- Structure: `get_datastructure` (memoised, shows the key template),
  `get_codelist`, and `available`/`nobs` over `/availableconstraint`.
- Data: `get_data` returning long/tidy `DataFrame`s with `period::Date`
  (period start) and `freq`; local label joining (`labels = true`);
  `read_sdmx_csv`; `to_wide`; `to_timearray` via a TimeSeries.jl extension.
- Safety under ISTAT's 5 requests/minute limit: persistent response cache,
  cross-process rate limiter, persisted ban sentinel, request budgets
  (`with_budget`), offline mode.
- Curated shortcuts, codes verified live 2026-08: `industrial_production`
  (115_333), `gdp` (163_156), `consumer_prices` (167_745, base 2025),
  `unemployment` (151_874).
