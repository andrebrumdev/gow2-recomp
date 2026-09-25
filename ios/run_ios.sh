#!/bin/bash
# run_ios.sh CONSOLE_LOG [ENV_JSON] -- launches the installed app with its
# console attached. ENV_JSON (e.g. '{"PS3_TRACE_FPS":"1"}') is the launch
# environment, which wins over the bundled recipe and Documents/gow2.override.env.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/ios_env.sh"
LOG="${1:?usage: run_ios.sh CONSOLE_LOG [ENV_JSON]}"
[ -n "$DEV" ] || { echo "set GOW2_IOS_DEVICE in local.env" >&2; exit 1; }
ARGS=(--device "$DEV" --console --terminate-existing)
[ -n "${2:-}" ] && ARGS+=(-e "$2")
exec xcrun devicectl device process launch "${ARGS[@]}" "$BUNDLE" > "$LOG" 2>&1
