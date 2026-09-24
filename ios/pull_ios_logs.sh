#!/bin/bash
# pull_ios_logs.sh OUT_DIR -- copies Documents/gow2.log (the app's own log) from the device.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/ios_env.sh"
OUT="${1:?usage: pull_ios_logs.sh OUT_DIR}"
mkdir -p "$OUT"
xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source Documents/gow2.log --destination "$OUT/gow2.log" > /dev/null
echo "GOW2_IOS_LOG=$OUT/gow2.log"
