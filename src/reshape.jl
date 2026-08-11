# Reshaping: to_wide and the TimeSeries.jl extension stub.
#
# `to_wide(df; by = :auto)` widens on every dimension that varies, joining
# codes with `.` in column names. Both reshapers error explicitly if more than
# one `freq` is present — a silently ragged result is a bug factory.
# `to_timearray` gets an erroring stub here ("requires TimeSeries.jl — run
# `using TimeSeries` first"); the real method lives in
# ext/IstatApiTimeSeriesExt.jl so DataFrame users never pay for it.
