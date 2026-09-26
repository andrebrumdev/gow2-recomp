#!/bin/bash
# Builds and runs the launcher's iOS checks (no device, no network).
# Usage: run.sh [out_dir]. Works from gow2-recomp and from the monorepo's games/gow2.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"          # launcher/macos
PORT="$(cd "$SRC/../.." && pwd)"                    # port root (ios/Sources lives there)
OUT="${1:-${TMPDIR:-/tmp}/ios_check}"
mkdir -p "$OUT"
cc -std=c11 -Wall -I"$PORT/ios/Sources" "$SRC/tests/ios_check/manifest_probe.c" \
    "$PORT/ios/Sources/gow2_ios_install_manifest.c" -o "$OUT/manifest_probe"
swiftc -swift-version 5 -target arm64-apple-macos14.0 \
    "$SRC"/Backend.swift "$SRC"/Settings.swift "$SRC"/OverlaySettingsFile.swift "$SRC"/IOS*.swift \
    "$SRC"/tests/ios_check/*.swift -o "$OUT/ios_check"
"$OUT/ios_check" "$OUT/manifest_probe"
