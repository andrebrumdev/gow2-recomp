#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
REC="$R/kit/golden/record.sh"
t_true "record.sh exists and parses" bash -n "$REC"
t_false "no args -> usage error" bash "$REC"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/game/USRDIR"; : > "$T/game/USRDIR/gow2.psarc"; : > "$T/EBOOT.ELF"
t_false "scratch inside gow2-recomp refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$R/scratch_here"
t_false "scratch inside ps3recomp refused"   bash "$REC" "$T/game" "$T/EBOOT.ELF" "$R/../ps3recomp/scratch_here"
t_true "the refusal created no dir inside the repos" test ! -e "$R/scratch_here" -a ! -e "$R/../ps3recomp/scratch_here"
# scratch reached through a symlink into a repo: refused before anything is created
ln -s "$R" "$T/repo_link"
t_false "scratch through a symlink into a repo refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/repo_link/scratch_link"
t_true "the symlink refusal created no dir inside the repo" test ! -e "$R/scratch_link"
# any git work tree (e.g. the user's playing tree), not only these two repos
mkdir -p "$T/other_repo" && git -C "$T/other_repo" init -q
t_false "scratch inside another git work tree refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/other_repo/s"
t_true "the refusal created no dir in the other work tree" test ! -e "$T/other_repo/s"
# the game folder: never used as, inside, or around the scratch; nothing in it is deleted
mkdir -p "$T/game/kit" "$T/game/stages" && : > "$T/game/kit/keep.txt"
t_false "scratch equal to the game folder refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/game"
t_true "the game folder kept its kit/ and stages/" test -f "$T/game/kit/keep.txt" -a -d "$T/game/stages"
t_false "scratch inside the game folder refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/game/USRDIR/s"
t_true "the refusal created no dir in the game folder" test ! -e "$T/game/USRDIR/s"
t_false "scratch containing the game folder refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T"
# a non-empty scratch that record.sh did not create is refused and left untouched
mkdir -p "$T/busy/kit" && : > "$T/busy/kit/keep.txt"
t_false "non-empty scratch without the record.sh marker refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/busy"
t_true "the refused scratch kept its files" test -f "$T/busy/kit/keep.txt"
t_false "missing PS3_GAME/USRDIR/gow2.psarc refused" bash "$REC" "$T/nogame" "$T/EBOOT.ELF" "$T/s"
t_true "record.sh --help prints usage" bash -c "bash '$REC' --help | grep -q 'record.sh <PS3_GAME>'"
# --write guards fail fast, before any copy or kit run
t_false "--write without KIT_TOOLS=py refused" env -u KIT_TOOLS bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/s1" --write --full
t_false "--write with KIT_TOOLS=cpp refused"  env KIT_TOOLS=cpp bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/s2" --write --full
t_false "--write without --full refused"      env KIT_TOOLS=py bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/s3" --write
if [ -f "$R/kit/golden/stages.tsv" ]; then
    t_false "--write over an existing golden without --replace refused" \
        env KIT_TOOLS=py bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/s4" --write --full
fi
t_true "the refused --write runs created no scratch tree" test ! -e "$T/s1/kit" -a ! -e "$T/s2/kit" -a ! -e "$T/s3/kit" -a ! -e "$T/s4/kit"
if [ ! -f "$R/kit/golden/stages.tsv" ]; then
    t_false "check mode without a golden refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/s6"
    t_true "the refused check created no scratch tree" test ! -e "$T/s6/kit"
fi
t_true "--help prints only the header" bash -c "! bash '$REC' --help | grep -q 'set -euo'"
t_false "--replace without --write refused" bash "$REC" "$T/game" "$T/EBOOT.ELF" "$T/s5" --replace
t_done
