# Loaded automatically when both IstatApi and DuckDB are in the session;
# provides the real `to_duckdb` / `catalogue_to_duckdb` (the core package
# carries erroring stubs, so plain-DataFrame users never depend on DuckDB).
#
# Nothing here touches the network: data reaches DuckDB only from DataFrames
# the caller already holds or from the shipped catalogue snapshots.
module IstatApiDuckDBExt

using IstatApi
using IstatApi.DataFrames: AbstractDataFrame, DataFrame, names, rename!
using DuckDB

const _Con = Union{DuckDB.DB,DuckDB.Connection}

# Quote an SQL identifier ("istat_115_333", "NOTE_ECON_ACTIVITY_NACE_2007").
_ident(s::AbstractString) = string('"', replace(s, '"' => "\"\""), '"')
_lit(s::AbstractString) = string('\'', replace(s, '\'' => "''"), '\'')

_exec(con, sql) = DuckDB.execute(con, sql)

function _columns(con, relation::AbstractString)
    res = DataFrame(_exec(con, "DESCRIBE SELECT * FROM " * _ident(relation)))
    return Dict(String(n) => String(t) for (n, t) in zip(res.column_name, res.column_type))
end

function _table_exists(con, table::AbstractString)
    res = DataFrame(_exec(con,
        "SELECT count(*) AS n FROM information_schema.tables " *
        "WHERE table_schema = current_schema() AND table_name = " * _lit(table)))
    return res.n[1] > 0
end

# Register `df` as a temporary view for the duration of `f(view)`. The name is
# unique per call so concurrent writers on one connection cannot collide.
function _with_view(f, con, df)
    view = string("__istatapi_staging_", time_ns())
    DuckDB.register_data_frame(con, df, view)
    try
        return f(view)
    finally
        DuckDB.unregister_data_frame(con, view)
    end
end

function _transaction(f, con)
    _exec(con, "BEGIN TRANSACTION")
    try
        r = f()
        _exec(con, "COMMIT")
        return r
    catch
        _exec(con, "ROLLBACK")
        rethrow()
    end
end

# SQL identifiers are case-insensitive, so a get_data result's derived `freq`
# column collides with the FREQ dimension. In the database it is stored as
# `period_freq` (next to `period`); read_duckdb renames it back.
function _db_frame(df::AbstractDataFrame)
    out = DataFrame(df; copycols = false)
    "freq" in names(out) && "period" in names(out) && rename!(out, "freq" => "period_freq")
    seen = Dict{String,String}()
    for c in names(out)
        prev = get(seen, lowercase(c), nothing)
        prev === nothing ||
            throw(ArgumentError("columns \"$prev\" and \"$c\" differ only in case; " *
                                "SQL identifiers are case-insensitive — rename one"))
        seen[lowercase(c)] = c
    end
    return out
end

function IstatApi.read_duckdb(con::_Con, query::AbstractString)
    sql = occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", query) ?
          "SELECT * FROM " * _ident(query) : String(query)
    df = DataFrame(_exec(con, sql))
    "period_freq" in names(df) && rename!(df, "period_freq" => "freq")
    return df
end

function IstatApi.to_duckdb(con::_Con, df::AbstractDataFrame;
                            table::Union{Nothing,AbstractString} = nothing,
                            mode::Symbol = :upsert)
    mode in (:upsert, :append, :replace) ||
        throw(ArgumentError("mode must be :upsert, :append or :replace, got :$mode"))
    tbl = table === nothing ? IstatApi._duckdb_table_name(df) : String(table)
    isempty(tbl) && throw(ArgumentError("empty table name"))
    keycols = String[]
    if mode === :upsert
        issubset(["DATAFLOW", "TIME_PERIOD"], names(df)) ||
            throw(ArgumentError("mode = :upsert needs a get_data result (DATAFLOW and " *
                                "TIME_PERIOD columns); use mode = :append or :replace"))
        keycols = ["DATAFLOW"; IstatApi._dimension_columns(df); "TIME_PERIOD"]
    end
    _with_view(con, _db_frame(df)) do view
        _transaction(con) do
            if mode === :replace || !_table_exists(con, tbl)
                _exec(con, "CREATE OR REPLACE TABLE $(_ident(tbl)) AS SELECT * FROM $(_ident(view))")
                return
            end
            # Schema drift: add columns the table lacks (labels, new NOTE_*)
            # rather than failing, so one table can accumulate queries.
            have = _columns(con, tbl)
            for (col, type) in sort!(collect(_columns(con, view)))
                haskey(have, col) && continue
                _exec(con, "ALTER TABLE $(_ident(tbl)) ADD COLUMN $(_ident(col)) $type")
            end
            if mode === :upsert
                missing_keys = setdiff(keycols, keys(have))
                isempty(missing_keys) ||
                    throw(ArgumentError("table $tbl lacks key column(s) " *
                                        join(missing_keys, ", ") *
                                        " — it holds a different dataflow; pass table = \"...\""))
                cond = join(("t.$(_ident(c)) IS NOT DISTINCT FROM v.$(_ident(c))" for c in keycols),
                            " AND ")
                _exec(con, "DELETE FROM $(_ident(tbl)) AS t USING $(_ident(view)) AS v WHERE $cond")
            end
            _exec(con, "INSERT INTO $(_ident(tbl)) BY NAME SELECT * FROM $(_ident(view))")
            return
        end
    end
    return tbl
end

function IstatApi.catalogue_to_duckdb(con::_Con; agency::AbstractString = "IT1",
                                      prefix::AbstractString = "istat_")
    flows = IstatApi.get_dataflows(; agency)
    dims = copy(IstatApi._catalogue("datastructures_$(agency).csv"))
    return [IstatApi.to_duckdb(con, flows; table = prefix * "dataflows", mode = :replace),
            IstatApi.to_duckdb(con, dims; table = prefix * "dimensions", mode = :replace)]
end

end # module
