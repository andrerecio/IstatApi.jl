# Re-capture the test fixtures from the live service.
#
#     julia --project test/fixtures/refresh.jl --yes
#
# Prints the full request plan and refuses to run without --yes. Runs under
# the package's live throttle (cached responses cost nothing). Never invoked
# by runtests.jl, never run in CI — the test suite itself is 100% offline.

using IstatApi
using JSON3

const HERE = @__DIR__
const ACCEPT = "application/json"

flows_url = string(IstatApi.ENDPOINT[], "/dataflow/IT1")
dsds_url  = string(IstatApi.ENDPOINT[], "/datastructure/IT1")

println("""
Request plan (cached responses cost nothing):
  1. GET $flows_url          → dataflows_IT1_slice.json (63-flow trim)
  2. GET $dsds_url           → datastructures_IT1_slice.json (2-DSD trim)
Throttle: $(rate_limit())
""")

if !("--yes" in ARGS)
    println("Refusing to run without --yes.")
    exit(1)
end

flows = JSON3.read(IstatApi._fetch(flows_url; accept = ACCEPT)).data.dataflows
keep = [f for f in flows if startswith(String(f.id), "115_333") ||
        startswith(String(f.id), "101_1015") ||
        String(f.id) in ("163_156", "167_744", "151_874")]
append!(keep, Iterators.take((f for f in flows if !(f in keep)), 50))
write(joinpath(HERE, "dataflows_IT1_slice.json"),
      JSON3.write((data = (dataflows = keep,),)))
println("dataflows_IT1_slice.json: $(length(keep)) flows")

dsds = JSON3.read(IstatApi._fetch(dsds_url; accept = ACCEPT)).data.dataStructures
keepd = [d for d in dsds if String(d.id) in ("DCSC_INDXPRODIND_1", "DCSP_COLTIVAZIONI")]
write(joinpath(HERE, "datastructures_IT1_slice.json"),
      JSON3.write((data = (dataStructures = keepd,),)))
println("datastructures_IT1_slice.json: $(length(keepd)) DSDs")
