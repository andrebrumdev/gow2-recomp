#!/bin/bash
# Builds and runs the launcher's Android checks (no device, no network).
# Usage: run.sh [out_dir]. Works from gow2-recomp and from the monorepo's games/gow2.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"          # launcher/macos
OUT="${1:-${TMPDIR:-/tmp}/android_check}"
mkdir -p "$OUT"
swiftc -swift-version 5 -target arm64-apple-macos14.0 \
    "$SRC"/IOSScripts.swift "$SRC"/AndroidBackend.swift "$SRC"/tests/android_check/*.swift -o "$OUT/android_check"
"$OUT/android_check"
