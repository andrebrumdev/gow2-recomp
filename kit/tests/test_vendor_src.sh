#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
. "$HERE/../lib/vendor_src.sh"
. "$HERE/../lib/release_guards.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
# a fake source tarball whose tree would trip the game-file guard if it were extracted
mkdir -p "$T/src/Lib-1.0/test"; echo "zlib licence (fake)" > "$T/src/Lib-1.0/LICENSE.txt"; : > "$T/src/Lib-1.0/test/tone.wav"
tar -czf "$T/Lib-1.0.tar.gz" -C "$T/src" Lib-1.0
SHA=$(shasum -a 256 "$T/Lib-1.0.tar.gz" | cut -d' ' -f1)
lock() { printf 'NAME=Lib\nVERSION=1.0\nURL=https://example.invalid/Lib-1.0.tar.gz\nSHA256=%s\nFILE=Lib-1.0.tar.gz\nLICENSE_MEMBER=%s\nLICENSE_AS=LICENSE.txt\nKIT_DIR=Lib\n' "$1" "$2"; }
lock "$SHA" Lib-1.0/LICENSE.txt > "$T/ok.lock"
lock "$(printf '%064d' 0)" Lib-1.0/LICENSE.txt > "$T/badsha.lock"
lock "$SHA" Lib-1.0/NOPE.txt > "$T/nolic.lock"
grep -v '^KIT_DIR=' "$T/ok.lock" > "$T/short.lock"

mkdir -p "$T/zip"
t_eq "Lib-src 1.0 $SHA" "$(vendor_source_tarball "$T/ok.lock" "$T/zip" "$T/Lib-1.0.tar.gz")" "prints the VERSIONS line"
t_true "tarball copied untouched" cmp -s "$T/Lib-1.0.tar.gz" "$T/zip/third_party/Lib/Lib-1.0.tar.gz"
t_true "licence shipped next to it" grep -q 'zlib licence' "$T/zip/third_party/Lib/LICENSE.txt"
t_false "nothing extracted: the game-file guard finds nothing" kit_find_game_files "$T/zip"
for c in badsha nolic short; do
    mkdir -p "$T/z_$c"
    t_false "$c lock refused" vendor_source_tarball "$T/$c.lock" "$T/z_$c" "$T/Lib-1.0.tar.gz"
done
t_eq "" "$(ls -A "$T/z_badsha")" "a sha mismatch copies nothing"
t_eq "" "$(ls -A "$T/z_short")" "a bad lock copies nothing"
# make_release wires both engine locks
has() { grep -qF -- "$2" "$1"; }
t_true "make_release vendors SDL2"   has "$R/kit/make_release.sh" 'vendor_source_tarball "$ENGINE/third_party/sdl2/sdl2.lock"'
t_true "make_release vendors FFmpeg" has "$R/kit/make_release.sh" 'vendor_source_tarball "$ENGINE/third_party/ffmpeg/ffmpeg.lock"'
t_true "make_release.sh parses" bash -n "$R/kit/make_release.sh"
t_done
