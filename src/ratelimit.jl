# Cross-process rate limiter and ban sentinel.
#
# Planned design (see CLAUDE.md): two gates — a 15 s minimum interval and at
# most 4 requests per rolling 60 s — with state in `<cache>/requests.log`
# guarded by FileWatching.Pidfile.mkpidlock plus an in-process ReentrantLock.
# The limit is per IP, so the limiter must be per machine, not per process.
# On 429 a `banned_until` sentinel is persisted (Retry-After, else 24 h;
# 1 h on an ambiguous 403); it is checked before every request.
# Public surface: set_rate_limit!, rate_limit, with_budget, requests_used,
# clear_ban!.
