# Data retrieval: get_data(flow; DIMS...) and get_data(flow, key).
#
# Returns a long/tidy DataFrame: DATAFLOW, one String column per dimension,
# TIME_PERIOD (verbatim), period::Date (period start), freq::String,
# OBS_VALUE::Union{Float64,Missing}, then status/note columns.
# `labels = true` joins labels LOCALLY from the cached codelist (avoids the
# ~3× wire cost of `;labels=both`); `:server` for one round trip. On a fully
# wildcarded key, consult nobs first and refuse above a configurable
# threshold (unfiltered queries risk HTTP 413).
