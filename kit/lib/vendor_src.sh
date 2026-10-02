# kit/lib/vendor_src.sh -- third-party SOURCE tarballs the release zip carries for the
# iPhone build (SDL2, FFmpeg; plan 2026-09-28 Phase 6), untouched and pinned by the
# engine's lock files (third_party/<name>/<name>.lock), so the kit downloads nothing.
# Never extracted in the zip (a source tree can trip the game-file guard); only the
# licence file is copied out next to the tarball.

_vlock() { sed -n "s/^$2=//p" "$1"; }

# vendor_source_tarball <lock> <zip_root> [tarball]  -> "<NAME>-src <VERSION> <SHA256>"
vendor_source_tarball() {
    local lock=$1 root=$2 tb=${3:-} dl=0 name ver url sha file lic licas dir d
    name=$(_vlock "$lock" NAME); ver=$(_vlock "$lock" VERSION); url=$(_vlock "$lock" URL)
    sha=$(_vlock "$lock" SHA256); file=$(_vlock "$lock" FILE); lic=$(_vlock "$lock" LICENSE_MEMBER)
    licas=$(_vlock "$lock" LICENSE_AS); dir=$(_vlock "$lock" KIT_DIR)
    if [ -z "$name" ] || [ -z "$ver" ] || [ -z "$url" ] || [ ${#sha} != 64 ] || [ -z "$file" ] \
       || [ -z "$lic" ] || [ -z "$licas" ] || [ -z "$dir" ]; then
        echo "bad lock file: $lock" >&2; return 1
    fi
    if [ -z "$tb" ]; then
        tb="$(mktemp "${TMPDIR:-/tmp}/vendor_src.XXXXXX")"; dl=1
        curl -fsSL "$url" -o "$tb" || { echo "download failed: $url" >&2; rm -f "$tb"; return 1; }
    fi
    if [ "$(shasum -a 256 "$tb" | cut -d' ' -f1)" != "$sha" ]; then
        echo "$name source sha256 mismatch (lock: $sha)" >&2
        [ "$dl" = 1 ] && rm -f "$tb"
        return 1
    fi
    d="$root/third_party/$dir"
    if ! tar -xOf "$tb" "$lic" > "$root/.vendor_licence.$$" 2>/dev/null || [ ! -s "$root/.vendor_licence.$$" ]; then
        rm -f "$root/.vendor_licence.$$"; [ "$dl" = 1 ] && rm -f "$tb"
        echo "no $lic in the $name tarball" >&2; return 1
    fi
    mkdir -p "$d"
    cp "$tb" "$d/$file"
    mv "$root/.vendor_licence.$$" "$d/$licas"
    [ "$dl" = 1 ] && rm -f "$tb"
    printf '%s-src %s %s\n' "$name" "$ver" "$sha"
}
