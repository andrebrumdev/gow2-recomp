#!/usr/bin/env bash
# kit/golden/record.sh -- run the kit pipeline in a fresh scratch tree and record
# (--write) or check the SHA-256 of every stage output against kit/golden/stages.tsv.
#
#   kit/golden/record.sh <PS3_GAME> <EBOOT.ELF> <scratch> [--write [--replace]] [--full] [--keep]
#
#   PS3_GAME   the user's game folder (read-only; setup.sh links it as extracted/)
#   EBOOT.ELF  the user's decrypted ELF (copied into the scratch tree)
#   scratch    an empty/absent dir (or one record.sh made) outside any git tree and the
#              game folder: gets a copy of the ELF and lifted code, never to be committed
#   --write    write kit/golden/stages.tsv in this repo instead of checking it. Only
#              with KIT_TOOLS=py and --full, and only if the run's ppu_final,
#              spu_final and movie_cache equal the committed kit/*.sha256
#   --replace  allow --write to overwrite an existing kit/golden/stages.tsv
#   --full     also run step 6 (engine build + link, minutes): stages
#              engine_metal_pre/post, hle_nids and spu_postbuild
#   --keep     KIT_STAGE_KEEP=1: keep a copy of every staged file under <scratch>/stages
# Env passed through: KIT_TOOLS, JOBS.
set -euo pipefail
usage() { sed -n '2,18p' "$0"; exit 2; }
[ "${1:-}" = --help ] && usage
[ $# -ge 3 ] || usage
GAME=$1; ELF=$2; S=$3; shift 3
WRITE=0; REPLACE=0; FULL=0; KEEP=0
for a in "$@"; do
    case "$a" in --write) WRITE=1 ;; --replace) REPLACE=1 ;; --full) FULL=1 ;; --keep) KEEP=1 ;; *) usage ;; esac
done
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
ENGINE="$(cd "${PS3_ENGINE_ROOT:-$HERE/../ps3recomp}" && pwd)"
. "$HERE/kit/lib/stages.sh"
GOLDEN="$HERE/kit/golden/stages.tsv"
MANIFESTS="ppu_final:kit/ppu_lift.sha256 spu_final:kit/spu_lift.sha256 movie_cache:kit/movie_cache.sha256"
refuse() { echo "record.sh: $*" >&2; exit 2; }
# --write guards that need no run: fail before anything is copied or built.
[ "$REPLACE" = 0 ] || [ "$WRITE" = 1 ] || refuse "--replace only makes sense with --write"
if [ "$WRITE" = 1 ]; then
    [ "${KIT_TOOLS:-}" = py ] || refuse "--write records the golden from the Python pipeline only: set KIT_TOOLS=py"
    [ "$FULL" = 1 ] || refuse "--write needs --full (the golden holds every stage)"
    [ ! -f "$GOLDEN" ] || [ "$REPLACE" = 1 ] || refuse "$GOLDEN exists: add --replace to overwrite it"
    for m in $MANIFESTS; do
        git -C "$HERE" diff --quiet HEAD -- "${m#*:}" || refuse "${m#*:} has uncommitted changes: the golden is checked against the committed manifests"
    done
else
    [ -f "$GOLDEN" ] || refuse "no $GOLDEN to check against: record it first with --write"
fi
[ -f "$GAME/USRDIR/gow2.psarc" ] || { echo "no USRDIR/gow2.psarc in $GAME" >&2; exit 2; }
[ -f "$ELF" ] || { echo "no ELF at $ELF" >&2; exit 2; }
inside_repo() { # <abs path>: rc 0 when it is inside either repository
    local r
    for r in "$HERE" "$ENGINE" "$(cd "$HERE" && pwd -P)" "$(cd "$ENGINE" && pwd -P)"; do
        case "$1/" in "$r/"*) return 0 ;; esac
    done
    return 1
}
case "$S" in /*) ;; *) S="$PWD/$S" ;; esac
# Resolve the scratch to a physical path BEFORE creating anything: the nearest existing
# ancestor through `pwd -P` (symlinks, ..), plus the missing components, which may not
# contain . or .. themselves.
physical_target() { # <abs path> -> physical abs path on stdout
    local p=$1 rest="" base
    while [ ! -d "$p" ]; do
        base=${p##*/}; case "$base" in .|..) return 1 ;; esac
        rest="/$base$rest"; p=${p%/*}; [ -n "$p" ] || p=/
    done
    p="$(cd "$p" && pwd -P)" || return 1
    [ "$p" = / ] && [ -z "$rest" ] && { echo /; return 0; }
    printf '%s%s\n' "${p%/}" "$rest"
}
refuse_scratch() { echo "scratch $S: $* -- refused (game-derived files)" >&2; exit 2; }
S="$(physical_target "$S")" || refuse_scratch "cannot resolve it (a missing component is . or ..)"
inside_repo "$S" && refuse_scratch "inside a repository"
# any git work tree (e.g. the user's playing tree), found from the nearest existing ancestor
A=$S; while [ ! -d "$A" ]; do A=${A%/*}; [ -n "$A" ] || A=/; done
git -C "$A" rev-parse --show-toplevel >/dev/null 2>&1 && refuse_scratch "inside a git work tree"
GAMEP="$(cd "$GAME" && pwd -P)"
case "$S/" in "$GAMEP/"*) refuse_scratch "equal to or inside the game folder $GAMEP" ;; esac
case "$GAMEP/" in "${S%/}/"*) refuse_scratch "contains the game folder $GAMEP" ;; esac
# Only an empty dir, or one a previous record.sh run created (marker), is reused:
# its kit/ and stages/ are deleted below.
MARK=.kit_record_scratch
if [ -d "$S" ] && [ ! -f "$S/$MARK" ] && [ -n "$(ls -A "$S")" ]; then
    refuse_scratch "not empty and not created by record.sh (no $MARK)"
fi
mkdir -p "$S"; : > "$S/$MARK"
K="$S/kit"; rm -rf "$K" "$S/stages"; mkdir -p "$K/gow2-recomp" "$K/ps3recomp"
# Tracked files as they are in the working tree (uncommitted edits included, so a
# change can be accepted before it is committed). A tracked file deleted but not yet
# committed makes tar fail: commit or restore it first.
copy_tracked() { (cd "$1" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$2"; }
copy_tracked "$HERE" "$K/gow2-recomp"
copy_tracked "$ENGINE" "$K/ps3recomp"
mv "$K/ps3recomp/games/gow2/lift_baseline" "$S/.lb" && rm -rf "$K/ps3recomp/games"
mkdir -p "$K/ps3recomp/games/gow2" && mv "$S/.lb" "$K/ps3recomp/games/gow2/lift_baseline"
PINNED="$(sed -n 's/^PINNED="\([^"]*\)".*/\1/p' "$HERE/kit/make_release.sh")"
for rev in $PINNED; do
    mkdir -p "$K/ps3recomp/tools_pinned/$rev"
    git -C "$ENGINE" archive "$rev" tools | tar -x -C "$K/ps3recomp/tools_pinned/$rev"
done
STOP=5; [ "$FULL" = 1 ] && STOP=6   # never step 7 (the launcher app is not a stage)
echo "== kit run in $K (stop after: ${STOP:-none})"
KIT_STAGE_DIR="$S/stages" KIT_STAGE_KEEP="$KEEP" KIT_STOP_AFTER="$STOP" PS3_ENGINE_ROOT="$K/ps3recomp" \
    "$K/gow2-recomp/kit/setup.sh" "$GAME" --elf "$ELF" > "$S/setup.log" 2>&1 \
    || { tail -30 "$S/setup.log" >&2; echo "kit run failed (log: $S/setup.log)" >&2; exit 1; }
CAND="$S/stages/stages.tsv"
if [ "$WRITE" = 1 ]; then
    # The run must reproduce the committed release manifests exactly.
    for m in $MANIFESTS; do
        st=${m%%:*}; mf=${m#*:}
        diff <(awk -F'\t' -v s="$st" '$1==s {print $3"  "$2}' "$CAND" | LC_ALL=C sort) \
             <(git -C "$HERE" show "HEAD:$mf" | LC_ALL=C sort) > "$S/manifest_$st.diff" \
            || refuse "stage $st does not match the committed $mf (see $S/manifest_$st.diff): golden NOT written"
    done
    NEW="$(mktemp "$HERE/kit/golden/.stages.tsv.XXXXXX")"
    {
        echo "# kit/golden/stages.tsv -- SHA-256 of every kit stage output (Kit sem Python)."
        echo "# Recorded $(date -u +%Y-%m-%dT%H:%MZ) by kit/golden/record.sh$( [ "$FULL" = 1 ] && echo ' --full')"
        echo "# gow2-recomp $(git -C "$HERE" rev-parse --short HEAD)$( [ -n "$(git -C "$HERE" status --porcelain --untracked-files=no)" ] && echo '+dirty')" \
             "ps3recomp $(git -C "$ENGINE" rev-parse --short HEAD)$( [ -n "$(git -C "$ENGINE" status --porcelain --untracked-files=no)" ] && echo '+dirty')" \
             "KIT_TOOLS=${KIT_TOOLS:-cpp} EBOOT_SHA=$(kit_sha256 "$ELF")"
        LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 "$CAND"
    } > "$NEW"
    mv "$NEW" "$GOLDEN"
    echo "== wrote $GOLDEN ($(grep -vc '^#' "$GOLDEN") records)"
else
    # a partial run (steps 1-5) cannot produce the step-6 stages
    G="$HERE/kit/golden/stages.tsv"
    if [ "$FULL" != 1 ]; then
        grep -v -e '^engine_metal_pre	' -e '^engine_metal_post	' -e '^hle_nids	' -e '^spu_postbuild	' "$G" > "$S/golden.partial.tsv"
        G="$S/golden.partial.tsv"
    fi
    stage_compare "$G" "$CAND"
fi
