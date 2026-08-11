# SDMX TIME_PERIOD parsing.
#
# Shapes: 2026-06, 2026-Q2, 2026-S1, 2026, 2026-06-15.
# `parse_period(s; at = :start)` returns the period's start Date by default
# (2026-Q2 → 2026-04-01, the ISO/Eurostat convention); `at = :last` gives the
# last month's first day. `period_frequency(s)` returns the frequency string.
# Not exported — `parse_period` is too generic a name for a user namespace.
