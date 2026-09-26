#!/usr/bin/env bash
# Each kit script must source stages.sh and capture its stages; the default path
# must stay a no-op (checked by test_stages.sh and by the golden run).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$HERE/../.."
. "$HERE/assert.sh"
has() { grep -qF -- "$2" "$1"; }
t_true "setup.sh sources stages.sh"         has "$R/kit/setup.sh" '. "$KIT/lib/stages.sh"'
for s in movie_cache ppu_raw ppu_patched ppu_final; do
    t_true "setup.sh captures $s"           has "$R/kit/setup.sh" "stage_capture $s"
done
for n in 3 4 5; do t_true "setup.sh stop-after $n" has "$R/kit/setup.sh" "kit_stop_after $n"; done
t_true "make_spu_lifts sources stages.sh"   has "$R/kit/make_spu_lifts.sh" '. "$GOW2/kit/lib/stages.sh"'
for s in spu_images spu_raw spu_final; do
    t_true "make_spu_lifts captures $s"     has "$R/kit/make_spu_lifts.sh" "stage_capture $s"
done
t_true "build_macos hashes the Metal source before the patchers" has "$R/build_macos.sh" "stage_capture engine_metal_pre"
t_true "build_macos hashes the Metal source after the patchers"  has "$R/build_macos.sh" "stage_capture engine_metal_post"
t_true "build_macos captures hle_nids"      has "$R/build_macos.sh" "stage_capture hle_nids"
t_true "build_macos captures spu_postbuild" has "$R/build_macos.sh" "stage_capture spu_postbuild"
for f in kit/setup.sh kit/make_spu_lifts.sh build_macos.sh; do t_true "$f parses" bash -n "$R/$f"; done
t_done
