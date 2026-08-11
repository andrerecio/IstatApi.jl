# IstatApi.jl

A Julia client for [ISTAT](https://www.istat.it)'s SDMX REST API — the official statistics service of the Italian National Institute of Statistics.

> ⚠️ **Work in progress.** This package is under active development and is **not currently working**. The API surface and internals are still being built — do not depend on it yet.

Planned features:

- Offline dataset discovery and search over a shipped catalogue snapshot (zero requests).
- Structure inspection: dimensions, codelists, and data availability (`availableconstraint`).
- Data retrieval as tidy `DataFrame`s, with optional wide and `TimeArray` reshaping.
- Built-in response caching and a cross-process rate limiter, respecting ISTAT's strict request limits (5 requests/minute per IP).

## License

MIT — see [LICENSE](LICENSE).
