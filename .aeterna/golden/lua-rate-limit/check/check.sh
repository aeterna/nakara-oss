#!/usr/bin/env bash
# Golden check for lua-rate-limit. Parent/child design:
#   - This parent holds AETERNA_GOLDEN_NONCE. It never loads fixture/ itself.
#   - It starts a child interpreter with that variable removed (env -u), so the nonce never reaches fixture code.
#   - The child loads fixture/ratelimit.lua, runs every expectation, and prints one success line on stdout
#     only when all of them held.
#   - The parent prints the nonce last, and only when the child exited 0 and its stdout is exactly that line.
set -u

if [ -z "${AETERNA_GOLDEN_NONCE:-}" ]; then
    echo "hint: AETERNA_GOLDEN_NONCE is not set. Run this check through 'aeterna-delegate qualify', not by hand." >&2
    exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
fixture="$here/../fixture"

out="$(env -u AETERNA_GOLDEN_NONCE lua "$here/child.lua" "$fixture")"
rc=$?

if [ "$rc" -ne 0 ]; then
    echo "lua-rate-limit: fixture did not pass (child exit $rc)" >&2
    exit 1
fi

# The child defines the exact expectation count; any other count is not a pass.
if ! [[ "$out" =~ ^GOLDEN_OK[[:space:]]lua-rate-limit[[:space:]]expectations=([0-9]+)$ ]] || [ "${BASH_REMATCH[1]}" -ne 39 ]; then
    echo "lua-rate-limit: child output was not the success line" >&2
    exit 1
fi

echo "$AETERNA_GOLDEN_NONCE"
