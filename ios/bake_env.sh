#!/bin/bash
# bake_env.sh ENV_RECIPE > gow2.env
# Bakes the play recipe -- env_gow2.sh plus the jogar_g2.sh overrides -- into
# sorted KEY=VALUE lines for the iOS app bundle (spec 2026-09-24 iOS,
# resolution 1). The caller's environment never leaks in (env -i). Container
# paths are not baked: the iOS host sets PS3_VFS_ROOT, PS3_MOVIE_CACHE,
# PS3_SAVEDATA_ROOT and GOW2_EBOOT at launch.
set -euo pipefail
RECIPE="${1:?usage: bake_env.sh path/to/env_gow2.sh}"
[ -f "$RECIPE" ] || { echo "no such recipe: $RECIPE" >&2; exit 1; }
env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/bash -c '
    set -a; . "$1"; set +a
    # jogar_g2.sh: play, not bench -- real cutscene length, sound on, no autostart pad.
    export PS3_MOVIE_DONE_MS=auto PS3_MUTE=0
    unset PS3_PAD_AUTOSTART PS3_VFS_ROOT PS3_MOVIE_CACHE PS3_FULLSCREEN PS3_METAL_VSYNC
    env' _ "$RECIPE" | LC_ALL=C grep -E '^PS3_[A-Z0-9_]*=' | LC_ALL=C sort
