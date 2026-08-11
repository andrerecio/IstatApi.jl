# SDMX keys

The one concept worth learning. A data key is `.`-separated with **one
position per dimension, in DSD order**:

```
M.IT.IND_PROD_21.Y.0020+0040+C
│ │  │           │  └─ ECON_ACTIVITY_NACE_2007: three codes, OR-ed with +
│ │  │           └─ ADJUSTMENT
│ │  └─ DATA_TYPE
│ └─ REF_AREA
└─ FREQ
```

- An **empty position** is a wildcard: `M....` selects every monthly series.
- `+` **within** a position is OR: one request returning several series.
  Never loop over codes — each request costs one fifth of ISTAT's per-minute
  budget.
- The dimension order and count come from the DSD
  (`get_dimensions(flow)`), never from a URL that happens to work — the
  server tolerates a spurious trailing dot, so a 200 is not evidence the key
  is right.

You rarely write keys by hand. `sdmx_key` builds and validates them:

```julia
sdmx_key("115_333"; FREQ = "M", ADJUSTMENT = "Y",
         ECON_ACTIVITY_NACE_2007 = ["0020", "0040", "C"])
# "M...Y.0020+0040+C"
```

Unknown dimension names and numeric codes throw `ArgumentError` locally —
`"0020"` as the integer `20` would silently select nothing, so numbers are
rejected outright.

`sdmx_url` composes the full request URL; `from`/`to` become
`startPeriod`/`endPeriod`. Note ISTAT's `endPeriod` can return up to one
extra year — trim after parsing if the boundary matters.
