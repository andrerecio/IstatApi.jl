# DuckDB storage — stubs for the IstatApiDuckDBExt package extension.
#
# DuckDB.jl is a weakdep: plain-DataFrame users never pay for a ~30 MB native
# library. The extension costs zero requests by construction — it only moves
# DataFrames the package already has (results, shipped catalogue snapshots)
# into a database, so storing data locally is a way to *spend fewer* of
# ISTAT's five requests per minute, never more.

"""
    to_duckdb(con, df; table = nothing, mode = :upsert) -> String

Store a [`get_data`](@ref) result in a DuckDB database and return the table
name. Requires DuckDB.jl (a package extension): run `using DuckDB` first.
`con` is a `DuckDB.DB` or `DuckDB.Connection`. **Zero requests.**

The table keeps the long schema — codes stay `VARCHAR` (`"0020"` is never
the number 20), `period` becomes `DATE`, missing observations become `NULL` —
with one rename: SQL identifiers are case-insensitive, so the derived `freq`
column (which would collide with the `FREQ` dimension) is stored as
`period_freq`. [`read_duckdb`](@ref) renames it back, so a stored result read
back works with [`to_wide`](@ref) again.

- `table` defaults to `istat_<flow id>` (e.g. `istat_115_333`) when `df`
  holds a single dataflow.
- `mode = :upsert` (default) replaces rows with the same `DATAFLOW`,
  dimension codes and `TIME_PERIOD`, then inserts — re-storing a refreshed
  query updates revised observations instead of duplicating them. Columns new
  to the table (e.g. `<DIM>_label` from `labels = true`) are added.
- `mode = :append` inserts without deduplicating; `mode = :replace` drops and
  recreates the table. Both also accept any `DataFrame` (codelists,
  `available` results, …); `:upsert` requires a `get_data` result.

```julia
using DuckDB
con = DBInterface.connect(DuckDB.DB, "istat.duckdb")
to_duckdb(con, industrial_production(from = "2020"))      # → "istat_115_333"
read_duckdb(con, "SELECT period, OBS_VALUE FROM istat_115_333 ORDER BY period")
```
"""
to_duckdb(con, df; kwargs...) =
    error("to_duckdb requires DuckDB.jl — run `using DuckDB` first")

"""
    read_duckdb(con, query) -> DataFrame

Run `query` — an SQL statement, or a bare table name meaning `SELECT *` from
it — against the DuckDB database `con` and return a `DataFrame`. The
`period_freq` column written by [`to_duckdb`](@ref) is renamed back to
`freq`, so `to_wide(read_duckdb(con, "istat_115_333"))` works. Requires
DuckDB.jl: run `using DuckDB` first. **Zero requests.**
"""
read_duckdb(con, query; kwargs...) =
    error("read_duckdb requires DuckDB.jl — run `using DuckDB` first")

"""
    catalogue_to_duckdb(con; agency = "IT1", prefix = "istat_") -> Vector{String}

Write the dataflow catalogue and the ordered DSD dimension lists to the DuckDB
database `con` as `<prefix>dataflows` and `<prefix>dimensions` (replacing
them), returning the table names. **Zero requests**: the source is the
shipped snapshot (or your refreshed copy — see [`get_dataflows`](@ref)).
Requires DuckDB.jl: run `using DuckDB` first.

The two tables join on `dsd`/`dsd_version`, which makes questions the
search functions cannot express a single query:

```julia
catalogue_to_duckdb(con)
DBInterface.execute(con, \"\"\"
    SELECT f.id, f.name_en
    FROM istat_dataflows f
    JOIN istat_dimensions d ON d.dsd = f.dsd AND d.version = f.dsd_version
    WHERE d.dimension = 'ECON_ACTIVITY_NACE_2007'
    ORDER BY f.id\"\"\")
```
"""
catalogue_to_duckdb(con; kwargs...) =
    error("catalogue_to_duckdb requires DuckDB.jl — run `using DuckDB` first")

# Default table name for a get_data result: istat_<flow id>, sanitised to a
# plain SQL identifier. Lives in core (pure, testable without DuckDB).
function _duckdb_table_name(df::AbstractDataFrame)
    "DATAFLOW" in names(df) ||
        throw(ArgumentError("cannot derive a table name: no DATAFLOW column — pass table = \"...\""))
    flows = unique(skipmissing(df.DATAFLOW))
    length(flows) == 1 ||
        throw(ArgumentError("cannot derive a table name from $(length(flows)) dataflows " *
                            "— pass table = \"...\""))
    id = split(_flow_ref(String(only(flows))), ',')[2]
    return "istat_" * replace(id, r"[^A-Za-z0-9_]" => "_")
end
