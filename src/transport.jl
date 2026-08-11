# Network funnel — the single point where IstatApi touches the network.
#
# Planned design (see CLAUDE.md):
#   * `_TRANSPORT[]` holds a swappable `(url, accept) -> (status, headers, body)`
#     function; tests replace it with a fixture transport, which is what makes
#     the offline test guarantee structural rather than aspirational.
#   * The real implementation wraps exactly one `HTTP.get` call with
#     `retry = false` — HTTP.jl retries idempotent requests by default, and a
#     silent 4× retry under ISTAT's 5 requests/minute limit is a self-inflicted
#     ban. `status_exception = false` so 404/429/403 arrive as data.
