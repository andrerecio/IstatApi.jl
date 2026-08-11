# Loaded automatically when both IstatApi and TimeSeries are in the session.
# Will hold the real `to_timearray` method; the core package only carries an
# erroring stub so plain-DataFrame users never depend on TimeSeries.
module IstatApiTimeSeriesExt

using IstatApi
using TimeSeries

end # module
