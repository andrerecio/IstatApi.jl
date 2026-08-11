# Re-capture the test fixtures from the live service.
#
#     julia --project test/fixtures/refresh.jl --yes
#
# Prints the full request plan and refuses to run without --yes. Runs under
# the package's live throttle (cached responses cost nothing). Never invoked
# by runtests.jl, never run in CI — the test suite itself is 100% offline.
#
# istat_ipi_2026-08.csv is not captured here: it is shared verbatim with
# NowcastIT.jl (one file, two purposes, no coupling).

using IstatApi
using JSON3

const HERE = @__DIR__
const JSONA = "application/json"
const XMLA = "application/xml"
const CSVLABELS = "application/vnd.sdmx.data+csv;version=1.0.0;labels=both"

flows_url = string(IstatApi.ENDPOINT[], "/dataflow/IT1")
dsds_url = string(IstatApi.ENDPOINT[], "/datastructure/IT1")
children_url = string(IstatApi.ENDPOINT[],
                      "/datastructure/IT1/DCSC_INDXPRODIND_1/1.0?references=children")
avail_url = string(IstatApi.ENDPOINT[],
                   "/availableconstraint/115_333/M...Y./all/ECON_ACTIVITY_NACE_2007")
labels_url = sdmx_url("115_333", "M.IT.IND_PROD_21.Y.0020"; from = "2026-01")

println("""
Request plan (5 requests, ~1 min under the throttle; cached responses cost nothing):
  1. GET $flows_url        → dataflows_IT1_slice.json (63-flow trim)
  2. GET $dsds_url         → datastructures_IT1_slice.json (2-DSD trim)
  3. GET $children_url     → dsd_115_333_children_trimmed.json
  4. GET $avail_url        → availableconstraint_115_333.xml (verbatim)
  5. GET $labels_url [labels=both] → istat_ipi_labels_2026.csv (verbatim)
Throttle: $(rate_limit())
""")

if !("--yes" in ARGS)
    println("Refusing to run without --yes.")
    exit(1)
end

# 1. dataflow slice
flows = JSON3.read(IstatApi._fetch(flows_url; accept = JSONA)).data.dataflows
keep = [f for f in flows if startswith(String(f.id), "115_333") ||
        startswith(String(f.id), "101_1015") ||
        String(f.id) in ("163_156", "167_744", "151_874")]
append!(keep, Iterators.take((f for f in flows if !(f in keep)), 50))
write(joinpath(HERE, "dataflows_IT1_slice.json"),
      JSON3.write((data = (dataflows = keep,),)))
println("dataflows_IT1_slice.json: $(length(keep)) flows")

# 2. datastructure slice
dsds = JSON3.read(IstatApi._fetch(dsds_url; accept = JSONA)).data.dataStructures
keepd = [d for d in dsds if String(d.id) in ("DCSC_INDXPRODIND_1", "DCSP_COLTIVAZIONI")]
write(joinpath(HERE, "datastructures_IT1_slice.json"),
      JSON3.write((data = (dataStructures = keepd,),)))
println("datastructures_IT1_slice.json: $(length(keepd)) DSDs")

# 3. IPI DSD with codelists, trimmed: CL_FREQ/CL_CORREZ whole, the huge ones
# cut down while keeping every code the data fixtures use
doc = JSON3.read(IstatApi._fetch(children_url; accept = JSONA))
keepn = Dict("CL_FREQ" => typemax(Int), "CL_CORREZ" => typemax(Int),
             "CL_TIPO_DATO7" => 12, "CL_ATECO_2007" => 40, "CL_ITTER107" => 3)
cls = []
for cl in doc.data.codelists
    haskey(keepn, String(cl.id)) || continue
    codes = collect(Iterators.take(cl.codes, keepn[String(cl.id)]))
    for want in ("0020", "0040", "C", "01", "IND_PROD_21", "IT")
        c = findfirst(x -> String(x.id) == want, cl.codes)
        c === nothing && continue
        any(x -> String(x.id) == want, codes) || push!(codes, cl.codes[c])
    end
    push!(cls, (id = cl.id, name = get(cl, :name, ""), names = get(cl, :names, (;)),
                codes = codes))
end
write(joinpath(HERE, "dsd_115_333_children_trimmed.json"),
      JSON3.write((data = (dataStructures = doc.data.dataStructures, codelists = cls),)))
println("dsd_115_333_children_trimmed.json: $(length(cls)) codelists")

# 4. availableconstraint, verbatim
write(joinpath(HERE, "availableconstraint_115_333.xml"),
      IstatApi._fetch(avail_url; accept = XMLA))
println("availableconstraint_115_333.xml")

# 5. labels=both extract, verbatim (the quoted-field and server-labels test)
write(joinpath(HERE, "istat_ipi_labels_2026.csv"),
      IstatApi._fetch(labels_url; accept = CSVLABELS))
println("istat_ipi_labels_2026.csv")
