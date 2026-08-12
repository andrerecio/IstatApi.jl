# # IstatApi.jl — basic usage
#
# A start-to-finish tour of the intended workflow:
#
#     discover → inspect → filter → retrieve
#
# Run it from the repository root with:
#
#     julia --project examples/basic_usage.jl
#
# Network use: steps 1–2a cost zero requests (the catalogue ships with the
# package). The rest makes at most 3 throttled requests on the first run
# (structure, availability, data) and 0 on later runs — every response is
# cached on disk. ISTAT allows 5 requests/minute per IP; the built-in rate
# limiter paces everything automatically, so the pauses you may notice are
# deliberate.

using IstatApi

# ── 1. Discover — zero requests ─────────────────────────────────────────────
# The full ISTAT catalogue (4,896 dataflows) ships with the package, so
# search works offline, in English or Italian.

println("Searching the catalogue for “industrial production”…\n")
hits = search_dataflow("industrial production")
show(stdout, first(hits, 5))
println("\n")

flow = "115_333"   # monthly industrial production index
println("Picked dataflow $flow: ", get_dataflow(flow).name_en, "\n")

# ── 2a. Inspect the key template — zero requests ────────────────────────────
# An SDMX key has one position per dimension, in this exact order.

dims = get_dimensions(flow)
println("Dimensions of $flow (key order): ", join(dims, ", "), "\n")

# ── 2b. Inspect codes — one cached request ──────────────────────────────────
# `available` tells you which codes actually have data under a partial key —
# a ~3 KB request, far cheaper than a wrong guess. (`nobs` sizes the whole
# query the same way before you pay for it.)

println("Which NACE activities have monthly, adjusted data?\n")
avail = available(flow, "ECON_ACTIVITY_NACE_2007"; FREQ = "M", ADJUSTMENT = "Y")
show(stdout, first(avail, 8))
println("\n")

# ── 3. Filter and retrieve — one request, then cached ───────────────────────
# UPPERCASE keywords are dimensions, validated against the data structure
# (a typo throws locally, before any request is spent). lowercase keywords
# are options. A vector of codes is ONE `+`-joined request returning several
# series — never loop over codes.

df = get_data(flow;
              FREQ = "M",
              REF_AREA = "IT",
              DATA_TYPE = "IND_PROD_21",
              ADJUSTMENT = "Y",
              ECON_ACTIVITY_NACE_2007 = ["0020", "C"],   # two series, one request
              from = "2020",
              labels = true)   # English labels joined locally, no extra wire cost

println("Long/tidy result — codes stay Strings, absent values are `missing`:\n")
show(stdout, first(df, 6))
println("\n")

# Reshape: one column per series, indexed by period-start dates.
w = to_wide(df)
println("Wide form:\n")
show(stdout, first(w, 6))
println("\n")

# ── Curated shortcuts ────────────────────────────────────────────────────────
# Each shortcut documents the exact `get_data` call it wraps (see its
# docstring), so you can always drop down a level. Uncomment to try — each
# costs one throttled request the first time:
#
# industrial_production(from = "2020")
# gdp(from = "2020")              # quarterly GDP, latest vintage
# consumer_prices(from = "2026")  # NIC index, base 2025 = 100
# unemployment(from = "2020")     # headline rate, ages 15–74

println("Done. Re-running this script costs zero requests — it's all cached.")
