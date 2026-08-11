# Getting started

The intended workflow is **discover → inspect → filter → retrieve**, and only
the last step (plus codelists) touches the network.

## 1. Discover — zero requests

The full ISTAT catalogue ships with the package, so search works offline:

```julia
using IstatApi

search_dataflow("industrial production")   # ranked matches, EN + IT names
search_dataflow("produzione industriale")  # Italian works too
get_dataflow("115_333")                    # one catalogue row
```

## 2. Inspect — zero requests for dimensions

```julia
get_dimensions("115_333")
# 5-element Vector{String}:
#  "FREQ", "REF_AREA", "DATA_TYPE", "ADJUSTMENT", "ECON_ACTIVITY_NACE_2007"
```

Codelists ride along with the full data structure (one request, then cached):

```julia
ds = get_datastructure("115_333")   # display() prints the key template
get_codelist("115_333", "ADJUSTMENT")
```

A codelist holds *every* code — to see which codes actually have data here,
and to size a query before paying for it (~3 KB each):

```julia
available("115_333", "ECON_ACTIVITY_NACE_2007"; FREQ = "M", ADJUSTMENT = "Y")
nobs("115_333"; FREQ = "M", ADJUSTMENT = "Y")
```

## 3. Filter and retrieve

Uppercase keywords are dimensions (validated against the DSD — typos throw
before any request); lowercase keywords are options. A vector is one
`+`-joined request returning several series — never loop over codes.

```julia
df = get_data("115_333";
              FREQ = "M", REF_AREA = "IT", DATA_TYPE = "IND_PROD_21",
              ADJUSTMENT = "Y",
              ECON_ACTIVITY_NACE_2007 = ["0020", "0040", "C"],
              from = "2015")
```

The result is a long/tidy `DataFrame` with `period::Date` (period start) and
`freq::String` alongside the verbatim `TIME_PERIOD`. Reshape it:

```julia
to_wide(df)                 # one column per series
using TimeSeries
to_timearray(df)            # TimeArray via the package extension
```

`labels = true` joins English labels locally from the cached codelists —
free after the structure fetch, and one third of the wire cost of asking the
server.

## Curated shortcuts

```julia
industrial_production()               # 115_333
gdp()                                 # 163_156, latest vintage
consumer_prices()                     # 167_745, NIC base 2025
unemployment()                        # 151_874, headline rate 15–74
```

Each docstring names its dataflow and fixed codes, so you can drop down to
`get_data` whenever a definition drifts.
