#!/usr/bin/env bash
# kit/make_sha256sums.sh: one sorted line per zip, verifiable with shasum -c, refuses an empty
# directory, ignores non-zip files, and --check catches a changed zip.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/assert.sh"
S="$HERE/../make_sha256sums.sh"
quiet() { "$@" >/dev/null 2>&1; }
T=$(t_tmp); trap 'rm -rf "$T"' EXIT

mkdir -p "$T/rel" "$T/empty"
printf 'kit b\n' > "$T/rel/gow2-recomp-kit-macos-20260930-b323750.zip"
printf 'kit a\n' > "$T/rel/gow2-recomp-kit-macos-20260923-0000000.zip"
printf 'kit c\n' > "$T/rel/kit with space.zip"
printf 'notes\n' > "$T/rel/NOTES.md"

t_true "writes SHA256SUMS" quiet bash "$S" "$T/rel"
t_eq 3 "$(wc -l < "$T/rel/SHA256SUMS" | tr -d ' ')" "one line per zip (non-zip files ignored)"
t_false "NOTES.md is not listed" grep -q "NOTES.md" "$T/rel/SHA256SUMS"
first="$(head -1 "$T/rel/SHA256SUMS" | sed 's/^[0-9a-f]*  //')"
t_eq "gow2-recomp-kit-macos-20260923-0000000.zip" "$first" "lines sorted by file name"
want="$(printf 'kit a\n' | shasum -a 256 | cut -d' ' -f1)"
got="$(head -1 "$T/rel/SHA256SUMS" | cut -d' ' -f1)"
t_eq "$want" "$got" "hash matches shasum -a 256"
t_true "shasum -c accepts the file" quiet sh -c "cd '$T/rel' && shasum -a 256 -c SHA256SUMS"
t_true "--check passes on an untouched release" quiet bash "$S" --check "$T/rel"
printf 'tampered\n' >> "$T/rel/gow2-recomp-kit-macos-20260930-b323750.zip"
t_false "--check fails after a zip changes" quiet bash "$S" --check "$T/rel"
t_false "empty directory is refused" quiet bash "$S" "$T/empty"
t_false "no SHA256SUMS file is not left behind in an empty dir" test -e "$T/empty/SHA256SUMS"
t_false "missing argument is refused" quiet bash "$S"
t_false "--check without SHA256SUMS fails" quiet bash "$S" --check "$T/empty"
t_done
