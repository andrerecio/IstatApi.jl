# Data structures (DSDs), codelists and availability.
#
# `DataStructure` carries agency/id/version, the ordered dimension list,
# codelist_of, cached codelists and attributes; its show method prints the key
# template (e.g. FREQ.REF_AREA.DATA_TYPE.ADJUSTMENT.ECON_ACTIVITY_NACE_2007).
# `available`/`nobs` wrap /availableconstraint — ~3 KB answers to "which codes
# have data HERE" and "how many observations would this key return", the
# package's best request-savers. `get_codelist` must warn that a codelist
# holds every code, not only those with data in this dataflow.
# Public surface: get_datastructure, get_dimensions, get_codelist, available,
# nobs.
