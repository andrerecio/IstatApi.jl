# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

**Core implemented, pre-registration.** `IstatApi.jl` (module `IstatApi`, Julia ≥ 1.10) is a public, registrable Julia client for ISTAT's SDMX 2.1 REST API. The v0.1.0 surface (transport/limiter/cache, discovery, structure, data, reshaping, the IPI shortcut) is implemented with a fully offline test suite; remaining before registration: the `gdp`/`consumer_prices`/`unemployment` shortcuts (need live code verification), docs pages, CHANGELOG. The full design document lives in `IstatApi.jl-PLAN.md` — **local-only and gitignored**; read it first if it exists. Structural model: [`gragusa/FredApi.jl`](https://github.com/gragusa/FredApi.jl) (small files grouped by concern, flat API of plain functions — but note it has no tests and known bugs; copy the spirit, not the code). Ergonomics model: [`Attol8/istatapi`](https://github.com/Attol8/istatapi) (discover → inspect → filter → retrieve).

## Commands

```bash
julia --project -e 'using Pkg; Pkg.test()'      # full suite — must pass with zero network
julia --project=docs docs/make.jl               # docs build, doctest = true, warnonly = false
```

Run a single test file by `include`-ing it from a REPL with the test environment active, or temporarily narrowing `test/runtests.jl`.

- Tests are **100% offline**: `runtests.jl` sets `ENV["ISTATAPI_OFFLINE"] = "1"` and `ENV["ISTATAPI_CACHE_DIR"] = mktempdir()` **before** `using IstatApi`, then swaps in a fixture transport. CI also sets `ISTATAPI_OFFLINE: '1'` as a job-level env var.
- `test/live_tests.jl` is the only network-touching test. Never run it from CI or `runtests.jl`.
- `test/fixtures/refresh.jl` and `dev/refresh_catalogue.jl` require `--yes`, print their request plan first, and run under the live throttle. Never automate them.

## The one governing constraint

**ISTAT allows 5 requests per minute per IP; exceeding it blocks the IP for 1–2 days.** Every major design choice — shipped snapshots, response cache, cross-process rate limiter, persisted ban sentinel, `retry = false` — exists to manage this. Never add code that can issue uncounted or repeated requests.

Endpoint: `https://esploradati.istat.it/SDMXWS/rest` (no authentication). Key endpoints: `/dataflow/IT1` (all 4,896 flows), `/datastructure/IT1` (all 892 DSDs with ordered dimension lists in one request), `/availableconstraint/{flow}/{key}/all/{dim}` (~3 KB, codes that actually have data + `obs_count`), `/data/{flowRef}/{key}` with `Accept: application/vnd.sdmx.data+csv;version=1.0.0`.

## Architecture

- **Single swappable transport.** Every request funnels through one function stored in `const _TRANSPORT = Ref{Any}(_http_get)` (`(url, accept) -> (status, headers, body)`), wrapping a single `HTTP.get` call. This is the keystone of the offline test strategy: tests replace `_TRANSPORT[]` with a fixture transport that records URLs, so `get_data`/`get_datastructure`/`get_dataflows` are tested end-to-end (URL construction, headers, parsing, caching, label joins) and tests assert the *exact* URLs and request counts.
- **Two shipped catalogue snapshots** — `data/dataflows_IT1.csv` and `data/datastructures_IT1.csv` (trimmed products of the two catalogue requests). Search, dimension lookup and key construction therefore cost **zero requests, offline**. Loaded lazily into a `Ref` on first use — **never in `__init__`, never during precompilation**. Resolution order: user's refreshed cache copy → shipped snapshot → `refresh = true`. All snapshot access goes through one internal `_catalogue_path()` (planned Artifact migration point).
- **Cache** in a Scratch.jl scratchspace (`ENV["ISTATAPI_CACHE_DIR"]` → Preferences → `@get_scratch!`), **not** inside the package dir. Filenames are `sha256(url * "\n" * accept)` (16 hex chars + readable prefix) because `+`-joined keys can exceed 255 chars. Atomic `dest.part` → `mv` writes with a `.meta.json` sidecar. Cache hits never touch the rate limiter.
- **Cross-process rate limiter**: 15 s minimum interval + max 4 per rolling 60 s, state in `<cache>/requests.log` guarded by `FileWatching.Pidfile.mkpidlock` plus an in-process `ReentrantLock`. It must be cross-process because the ban is per IP — a second Julia session or Pluto notebook shares the budget.
- **Ban sentinel**, persisted across sessions: on 429 write `<cache>/banned_until` (honour `Retry-After`, else 24 h); on an *ambiguous* 403 use **1 h** (a malformed URL also 403s). Checked before every request; throws `BannedError` with no network. `clear_ban!()` is the exported escape hatch. 404/empty body → `NoDataError`, no sentinel. Never trigger a 429 deliberately, even in testing — it costs a real 1–2 day ban.
- **TimeSeries.jl is a weakdep** (`ext/IstatApiTimeSeriesExt.jl`), with an erroring stub in core. Do not promote it to a dep. Do not depend on `SDMX.jl` (parses SDMX-JSON data messages; we use SDMX-CSV for data). Use JSON3, not JSON.jl.

### API surface at a glance

| Layer | Functions | Requests |
|---|---|---|
| Discovery | `get_dataflows`, `get_dataflow`, `search_dataflow` | 0 (shipped snapshot) |
| Structure | `get_datastructure`, `get_dimensions`, `get_codelist`, `available`, `nobs`, `sdmx_key`, `sdmx_url` | 0 for dimensions; 1 for codelists/availability |
| Data | `get_data(flow; DIMS...)` → long `DataFrame`; `read_sdmx_csv`, `to_wide`, `to_timearray` (ext) | 1 per uncached query |
| Control | `set_cache_dir!`, `clear_cache!`, `set_rate_limit!`, `with_budget`, `offline!`/`online!`, `clear_ban!` | 0 |
| Shortcuts | `industrial_production` (115_333), `gdp` (163_156), `consumer_prices` (167_744), `unemployment` (151_874) | 1 |

Errors: `abstract IstatError` with `OfflineError`, `BudgetExhaustedError`, `RateLimitError`, `BannedError`, `NoDataError` (points users at `available`), `RequestFailed`.

## SDMX keys

A key is `.`-separated with one position per dimension **in DSD order**; empty position = wildcard, `+` within a position = OR — so `M.IT.IND_PROD_21.Y.0020+0040+C` is *one* request returning three series. Never loop over codes. The server tolerates a spurious trailing dot, so a working URL is not evidence of the dimension count — always read it from the DSD. Build flowRefs **without** a version by default (the server resolves latest).

## Hard invariants — never break these

- **`retry = false` on `HTTP.get`.** HTTP.jl silently retries idempotent requests by default; a 4× retry under a 5/min limit is a self-inflicted ban. Asserted in a test.
- **Never weaken TLS** and send an honest `IstatApi.jl/<version>` User-Agent. (The Python `istatapi` does both wrong: `verify=False`, unsafe-renegotiation SSL flags, Chrome UA spoof — it targets the legacy `http://sdmx.istat.it` endpoint. Copy its ergonomics, none of its transport.)
- **SDMX codes are `String`s**: `"0020"` must never become the integer `20`. The CSV parser must also handle quoted fields containing commas (`NOTE_*` columns).
- **`missing`, not `NaN`**, for absent observations.
- **Period-start date convention**: `2026-Q2 → 2026-04-01`, with `freq::String` carried alongside; `parse_period(s; at = :start)` with `at ∈ (:start, :last)`. `TIME_PERIOD` shapes: `2026-06`, `2026-Q2`, `2026-S1`, `2026`, `2026-06-15`.
- **Kwarg rule**: lowercase kwargs are options (`from`, `to`, `labels`, `cache`, `force`); UPPERCASE kwargs are dimensions, validated against the DSD with `ArgumentError` on typos (catching mistakes locally instead of spending a request).
- **Deterministic search order**: score desc, then `id` asc — tests depend on a total order.
- `labels = true` joins labels **locally** from the cached codelist (avoids the ~3× wire cost of `;labels=both`); `:server` for the one-round-trip variant.
- Reshapers (`to_wide`, `to_timearray`) **error if more than one `freq` is present**.

## Service gotchas (from the ondata guide, verified 2026-08)

- `endPeriod` returns roughly one extra year beyond the requested bound — prefer `lastNObservations`/`firstNObservations` for exploration, or trim after parsing.
- Format negotiation is Accept-header-only; there is no `?format=` query parameter.
- Unfiltered data queries can be enormous (HTTP 413 risk) — `get_data` should consult `nobs` on wildcarded keys and refuse above a threshold.
- `Content-Encoding: gzip` is not reliably honoured; send `Accept-Encoding: gzip` anyway and treat compression as a bonus.

## References

- [ondata guida-api-istat](https://ondata.github.io/guida-api-istat/) — the best practical guide to the ISTAT SDMX API (Italian).
- [Attol8/istatapi](https://github.com/Attol8/istatapi) — Python client; ergonomics model and anti-pattern catalogue.
- [gragusa/FredApi.jl](https://github.com/gragusa/FredApi.jl) — structural model.
- Positioning: `DBnomics.jl` mirrors ISTAT with no per-IP limit — the README must say when to prefer it vs this package (official endpoint, full current catalogue, ISTAT's own codes/labels, codelist vintage control). `SDMX.jl` reads SDMX-JSON files, no HTTP.
