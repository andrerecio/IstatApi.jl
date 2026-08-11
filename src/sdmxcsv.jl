# SDMX-CSV parsing (Accept: application/vnd.sdmx.data+csv;version=1.0.0).
#
# Columns: DATAFLOW, <dimensions...>, TIME_PERIOD, OBS_VALUE, OBS_STATUS,
# NOTE_*, BASE_PER, UNIT_MEAS, UNIT_MULT. Codes are Strings — "0020" must
# never become the integer 20 — and NOTE_* fields contain quoted commas, so a
# naive line splitter is a bug. Empty OBS_VALUE parses to `missing`, not NaN.
# Public surface: read_sdmx_csv.
