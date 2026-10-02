#!/usr/bin/env bash
# kit/make_sha256sums.sh -- write SHA256SUMS for the kit zips of a release (maintainers).
#
#   ./kit/make_sha256sums.sh <dir>           # writes <dir>/SHA256SUMS for every <dir>/*.zip
#   ./kit/make_sha256sums.sh --check <dir>   # verifies <dir>/SHA256SUMS against the zips
#
# The file uses the format of `shasum -a 256` / `sha256sum` (hash, two spaces, file name), one line
# per zip, sorted by name, so a user checks a download with `shasum -a 256 -c SHA256SUMS`. Only
# *.zip files are listed; the script never creates, tags or uploads a release (docs/RELEASING.md).
# It verifies what it wrote before returning. Exit 1 when there is no zip or a check fails.
set -euo pipefail

sha256() {   # sha256 <file>... -> "<hash>  <file>" lines
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"
    else sha256sum "$@"; fi
}
sha256_check() {   # sha256_check <sumsfile>
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 -c "$1"
    else sha256sum -c "$1"; fi
}

mode=write
if [ "${1:-}" = --check ]; then mode=check; shift; fi
[ $# -eq 1 ] && [ -d "$1" ] || { echo "uso: $0 [--check] <dir com os .zip>" >&2; exit 2; }
DIR="$(cd "$1" && pwd)"
cd "$DIR"

if [ "$mode" = check ]; then
    [ -f SHA256SUMS ] || { echo "sem SHA256SUMS em $DIR" >&2; exit 1; }
    sha256_check SHA256SUMS
    exit $?
fi

zips=()
while IFS= read -r z; do zips+=("$z"); done < <(LC_ALL=C ls -1 | grep -E '\.zip$' | LC_ALL=C sort || true)
[ "${#zips[@]}" -gt 0 ] || { echo "nenhum .zip em $DIR" >&2; exit 1; }
tmp="$(mktemp "$DIR/.SHA256SUMS.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
sha256 "${zips[@]}" > "$tmp"
mv "$tmp" SHA256SUMS
trap - EXIT
sha256_check SHA256SUMS >/dev/null
echo "$DIR/SHA256SUMS (${#zips[@]} zip(s))"
