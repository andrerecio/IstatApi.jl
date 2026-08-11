# Refresh the shipped catalogue snapshots in data/.
#
#     julia --project dev/refresh_catalogue.jl --yes
#
# Makes up to TWO live requests to ISTAT (zero if the responses are already in
# the IstatApi cache), runs under the package's own throttle, and rewrites:
#
#     data/dataflows_IT1.csv        id, agency, version, name_en, name_it,
#                                   dsd, dsd_version, last_update, metadata_url
#     data/datastructures_IT1.csv   dsd, version, position, dimension, codelist
#     data/*.meta.toml              snapshot date, row counts, source URLs
#
# Never run from CI or from the test suite.

using IstatApi
using CSV, DataFrames, Dates, TOML

const DATA_DIR = normpath(joinpath(@__DIR__, "..", "data"))

plan = [
    ("dataflows_IT1", string(IstatApi.ENDPOINT[], "/dataflow/IT1"),
     IstatApi._parse_dataflows_json),
    ("datastructures_IT1", string(IstatApi.ENDPOINT[], "/datastructure/IT1"),
     IstatApi._parse_datastructures_json),
]

println("Request plan (cached responses cost nothing):")
for (name, url, _) in plan
    println("  GET $url  →  data/$name.csv")
end
println("Throttle: ", rate_limit(), ". Output: ", DATA_DIR)

if !("--yes" in ARGS)
    println("\nRefusing to run without --yes.")
    exit(1)
end

stamp = string(today())
for (name, url, parser) in plan
    body = IstatApi._fetch(url; accept = "application/json")
    df = parser(body)
    CSV.write(joinpath(DATA_DIR, "$name.csv"), df)
    open(joinpath(DATA_DIR, "$name.meta.toml"), "w") do io
        TOML.print(io, Dict("snapshot_date" => stamp, "rows" => nrow(df),
                            "source" => url))
    end
    println("$name.csv: $(nrow(df)) rows")
end
println("snapshot date: $stamp — done.")
