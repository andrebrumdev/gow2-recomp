#!/usr/bin/env bash
# Deprecated path: this file moved to scripts/smoke/smoke_intro_open_wall.sh on 2026-10-02 (map: scripts/README.md).
# Thin wrapper kept so old commands, docs and other checkouts keep working; remove after 2026-12-31.
# Same arguments, environment, working directory and exit code (exec).
# gow2-recomp:moved-to scripts/smoke/smoke_intro_open_wall.sh
exec bash "$(dirname "$0")/scripts/smoke/smoke_intro_open_wall.sh" "$@"
