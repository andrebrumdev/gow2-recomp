# kit/lib/cpython_src.sh -- the kit's fallback Python, as SOURCE (plan
# 2026-09-26-gow2-kit-sem-python, D4; Phase 5 removes it). The release zip carries
# the python.org tarball untouched and hash-pinned; setup.sh compiles it locally
# only when no Python >= 3.11 exists. No prebuilt executable ever ships in the kit.
# Licence: PSF License Agreement (Python 3.12), shipped as third_party/cpython/LICENSE.

_lock() { sed -n "s/^$2=//p" "$1"; }

# vendor_cpython_source <lock> <zip_root> [tarball]
vendor_cpython_source() {
    local lock=$1 root=$2 tb=${3:-} ver url sha dl=0 d
    ver=$(_lock "$lock" PYTHON_VERSION); url=$(_lock "$lock" PYTHON_URL); sha=$(_lock "$lock" PYTHON_SHA256)
    [ -n "$ver" ] && [ -n "$url" ] && [ ${#sha} = 64 ] || { echo "bad lock file: $lock" >&2; return 1; }
    if [ -z "$tb" ]; then
        tb="$(mktemp "${TMPDIR:-/tmp}/cpython.XXXXXX")"; dl=1
        curl -fsSL "$url" -o "$tb" || { echo "download failed: $url" >&2; rm -f "$tb"; return 1; }
    fi
    if [ "$(shasum -a 256 "$tb" | cut -d' ' -f1)" != "$sha" ]; then
        echo "CPython source sha256 mismatch (lock: $sha)" >&2
        [ "$dl" = 1 ] && rm -f "$tb"
        return 1
    fi
    d="$root/third_party/cpython"; mkdir -p "$d"
    cp "$tb" "$d/Python-$ver.tar.xz"
    tar -xJOf "$tb" "Python-$ver/LICENSE" > "$d/LICENSE" || { echo "no LICENSE in the tarball" >&2; return 1; }
    [ "$dl" = 1 ] && rm -f "$tb"
    printf 'cpython-src %s %s\n' "$ver" "$sha"
}

# kit_build_python <tarball> <sha256> <prefix> <workdir>
kit_build_python() {
    local tb=$1 sha=$2 prefix=$3 work=$4 src
    [ "$(shasum -a 256 "$tb" | cut -d' ' -f1)" = "$sha" ] || { echo "CPython source sha256 mismatch: $tb" >&2; return 1; }
    rm -rf "$work"; mkdir -p "$work"
    tar -xJf "$tb" -C "$work" || return 1
    src="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'Python-*' | head -1)"
    [ -n "$src" ] || { echo "no Python-* dir in $tb" >&2; return 1; }
    ( cd "$src" \
      && ./configure --prefix="$prefix" --without-ensurepip --disable-test-modules \
      && make -j "${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}" \
      && make install ) || return 1
    [ -x "$prefix/bin/python3" ] || { echo "make install produced no $prefix/bin/python3" >&2; return 1; }
    rm -rf "$work"
}
