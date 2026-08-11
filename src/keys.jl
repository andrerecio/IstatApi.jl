# SDMX key and URL construction.
#
# A key is `.`-separated, one position per dimension in DSD order; empty
# position = wildcard, `+` within a position = OR (one request, many series).
# The dimension count comes from the DSD — never inferred from a URL that
# happens to work (the server tolerates a spurious trailing dot). flowRefs are
# built WITHOUT a version by default; the server resolves to the latest.
# Kwarg rule: UPPERCASE kwargs are dimensions (validated against the DSD,
# ArgumentError on typos), lowercase kwargs are options.
# Public surface: sdmx_key, sdmx_url.
