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
