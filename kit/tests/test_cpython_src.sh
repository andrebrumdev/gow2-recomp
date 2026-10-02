#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/assert.sh"
. "$HERE/../lib/cpython_src.sh"
. "$HERE/../lib/pick_python.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
# A fake CPython source tree: configure writes a Makefile whose install copies a fake python3.
S="$T/src/Python-3.12.0"; mkdir -p "$S/Lib/test/audiodata"
: > "$S/Lib/test/audiodata/tone.wav"; echo "PSF LICENSE AGREEMENT (fake)" > "$S/LICENSE"
printf '#!/bin/sh\nexit 0\n' > "$S/fakepy"; chmod +x "$S/fakepy"
printf 'all:\n\t@true\ninstall:\n\tmkdir -p $(PREFIX)/bin && cp fakepy $(PREFIX)/bin/python3\n' > "$S/Makefile.in"
cat > "$S/configure" <<'CFG'
#!/bin/sh
for a in "$@"; do case "$a" in --prefix=*) P="${a#--prefix=}" ;; esac; done
{ echo "PREFIX=$P"; cat Makefile.in; } > Makefile
CFG
chmod +x "$S/configure"
tar -cJf "$T/Python-3.12.0.tar.xz" -C "$T/src" Python-3.12.0
SHA=$(shasum -a 256 "$T/Python-3.12.0.tar.xz" | cut -d' ' -f1)
printf 'PYTHON_VERSION=3.12.0\nPYTHON_URL=https://example.invalid/Python-3.12.0.tar.xz\nPYTHON_SHA256=%s\n' "$SHA" > "$T/ok.lock"
printf 'PYTHON_VERSION=3.12.0\nPYTHON_URL=https://example.invalid/Python-3.12.0.tar.xz\nPYTHON_SHA256=%064d\n' 0 > "$T/bad.lock"

# release side
mkdir -p "$T/zip"
t_eq "cpython-src 3.12.0 $SHA" "$(vendor_cpython_source "$T/ok.lock" "$T/zip" "$T/Python-3.12.0.tar.xz")" "prints the VERSIONS line"
t_true "tarball copied untouched" cmp -s "$T/Python-3.12.0.tar.xz" "$T/zip/third_party/cpython/Python-3.12.0.tar.xz"
t_true "licence shipped next to it" grep -q 'PSF LICENSE' "$T/zip/third_party/cpython/LICENSE"
t_eq "" "$(find "$T/zip" -iname '*.wav')" "nothing extracted in the zip tree (the game-data guard sees no .wav)"
mkdir -p "$T/zip2"
t_false "sha mismatch refused at release" vendor_cpython_source "$T/bad.lock" "$T/zip2" "$T/Python-3.12.0.tar.xz"
t_true "nothing written on mismatch" test ! -e "$T/zip2/third_party"

# setup side
t_true "build from source succeeds" kit_build_python "$T/Python-3.12.0.tar.xz" "$SHA" "$T/pfx" "$T/work"
t_true "python3 installed and qualifies" kit_py_ok "$T/pfx/bin/python3"
t_false "sha mismatch refused before building" kit_build_python "$T/Python-3.12.0.tar.xz" "$(printf '%064d' 0)" "$T/pfx2" "$T/work2"
t_true "nothing extracted on mismatch" test ! -e "$T/work2/Python-3.12.0"
t_done
