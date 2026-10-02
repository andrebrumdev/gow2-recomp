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
t_true "make_spu_lifts pins the HEAD lifter"  has "$R/kit/make_spu_lifts.sh" 'REV_HEAD=${SPU_LIFTER_HEAD_REV:-305dd109}'
t_false "make_spu_lifts no longer uses the moving tools/" has "$R/kit/make_spu_lifts.sh" 'T_HEAD="$PS3/tools"'
t_true "make_release ships the 4th pinned rev" has "$R/kit/make_release.sh" 'PINNED="5b004fc7 5f36a40e 11a1c3c5 305dd109"'
t_false "make_spu_lifts never runs patch_spu6_extra_funcs.py directly (its LIFTER is the moving tools/)" has "$R/kit/make_spu_lifts.sh" '"$PY" "$SPU6P"'
t_true "make_spu_lifts lifts spu6 through the helper" has "$R/kit/make_spu_lifts.sh" 'H spu6 "$W/img6.bin" "$B/spu6_v2"'
t_true "the spu6 helper overrides LIFTER with the pinned T_HEAD" has "$R/kit/make_spu_lifts.sh" 'm.LIFTER = pathlib.Path(os.environ["T_HEAD"]) / "spu_lifter.py"'
t_true "setup.sh builds ps3kit"               has "$R/kit/setup.sh" 'cmake -S "$ENGINE/tools/kit"'
t_true "setup.sh psarc via ps3kit"            has "$R/kit/setup.sh" '"$PS3KIT" psarc-extract'
t_true "make_spu_lifts images via ps3kit"     has "$R/kit/make_spu_lifts.sh" '"$PS3KIT" spu-images'
t_true "build_macos NIDs via ps3kit"          has "$R/build_macos.sh" '"$PS3KIT" hle-nids'
t_true "KIT_TOOLS validated"                  has "$R/kit/setup.sh" 'KIT_TOOLS must be py or cpp'
t_true "setup.sh drops an inherited PS3KIT on the py path" has "$R/kit/setup.sh" 'unset PS3KIT'
t_true "setup.sh captures the kit delta per-patch stage" has "$R/kit/setup.sh" 'stage_capture ppu_after/kit_delta "$HERE/$W" $PPU_FILES'
t_true "apply_all_patches captures after each patch"     has "$R/apply_all_patches.sh" 'stage_capture "ppu_after/$1" "$LIFT" $KIT_PPU_FILES'
t_true "apply_all_patches records order and status"      has "$R/apply_all_patches.sh" 'stage_record ppu_status "$1"'
t_true "apply_all_patches never keeps per-patch copies"  has "$R/apply_all_patches.sh" 'KIT_STAGE_KEEP=0 stage_capture'
t_true "apply_all_patches.sh parses"                      bash -n "$R/apply_all_patches.sh"
t_true "setup.sh builds the launcher app"        has "$R/kit/setup.sh" '"$HERE/launcher/macos/build_app.sh"'
t_true "setup.sh can stop before the app"        has "$R/kit/setup.sh" 'kit_stop_after 6'
t_true "record.sh --full stops before the app"   has "$R/kit/golden/record.sh" '[ "$FULL" = 1 ] && STOP=6'
t_true "README has the iPhone section"           has "$R/kit/README.md" '## Install on iPhone / iPad'
t_done
