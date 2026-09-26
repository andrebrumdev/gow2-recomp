#!/usr/bin/env bash
# Runs every kit bash test (no game data, no network).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$HERE"/test_*.sh; do bash "$t" || rc=1; done
exit $rc
