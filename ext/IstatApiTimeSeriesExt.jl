# Loaded automatically when both IstatApi and TimeSeries are in the session;
# provides the real `to_timearray` (the core package only carries an erroring
# stub so plain-DataFrame users never depend on TimeSeries).
module IstatApiTimeSeriesExt

using IstatApi
using TimeSeries

function IstatApi.to_timearray(df::IstatApi.DataFrames.AbstractDataFrame;
                               by = :auto)
    wide = IstatApi.to_wide(df; by)
    return TimeArray(wide; timestamp = :period)
end

end # module
