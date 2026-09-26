#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/assert.sh"
. "$HERE/../lib/stages.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src/sub"; printf 'abc' > "$T/src/a.txt"; printf 'xyz' > "$T/src/sub/b.txt"
SHA_ABC=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad

# no-op when KIT_STAGE_DIR is unset: no file, rc 0
unset KIT_STAGE_DIR KIT_STAGE_KEEP KIT_STOP_AFTER
t_true "capture without KIT_STAGE_DIR returns 0" stage_capture s1 "$T/src" a.txt
t_eq "" "$(ls -A "$T" | grep -v '^src$')" "capture without KIT_STAGE_DIR creates nothing"

# records stage, relpath, sha256
KIT_STAGE_DIR="$T/st" stage_capture s1 "$T/src" a.txt sub/b.txt
t_eq "s1	a.txt	$SHA_ABC" "$(head -1 "$T/st/stages.tsv")" "first record"
t_eq 2 "$(wc -l < "$T/st/stages.tsv" | tr -d ' ')" "two records"
t_false "missing file fails" env KIT_STAGE_DIR="$T/st" bash -c ". '$HERE/../lib/stages.sh'; stage_capture s1 '$T/src' nope.txt"
t_true "no copy without KIT_STAGE_KEEP" test ! -e "$T/st/s1/a.txt"
KIT_STAGE_DIR="$T/st2" KIT_STAGE_KEEP=1 stage_capture s1 "$T/src" sub/b.txt
t_true "KIT_STAGE_KEEP copies the file" cmp -s "$T/src/sub/b.txt" "$T/st2/s1/sub/b.txt"

# compare
printf '# golden\ns1\ta.txt\t%s\ns2\tc.txt\t%s\n' "$SHA_ABC" 1111 > "$T/g.tsv"
printf 's1\ta.txt\t%s\ns2\tc.txt\t1111\n' "$SHA_ABC" > "$T/same.tsv"
t_true "identical sets compare equal" stage_compare "$T/g.tsv" "$T/same.tsv"
printf 's1\ta.txt\t%s\ns2\tc.txt\t2222\n' "$SHA_ABC" > "$T/diff.tsv"
t_false "a changed hash fails" stage_compare "$T/g.tsv" "$T/diff.tsv"
t_eq "DIFF      s2	c.txt" "$(stage_compare "$T/g.tsv" "$T/diff.tsv" | grep '^DIFF')" "DIFF line names the file"
printf 's1\ta.txt\t%s\n' "$SHA_ABC" > "$T/miss.tsv"
t_false "a missing file fails" stage_compare "$T/g.tsv" "$T/miss.tsv"
t_true "stage filter ignores other stages" stage_compare "$T/g.tsv" "$T/miss.tsv" s1
printf 's1\ta.txt\t%s\ns2\tc.txt\t1111\ns3\tx\t9\n' "$SHA_ABC" > "$T/extra.tsv"
t_false "an extra file fails" stage_compare "$T/g.tsv" "$T/extra.tsv"
printf 's1\ta.txt\t%s\ns1\ta.txt\t0000\ns2\tc.txt\t1111\n' "$SHA_ABC" > "$T/conf.tsv"
t_false "two different hashes for one file fail" stage_compare "$T/g.tsv" "$T/conf.tsv"
: > "$T/empty.tsv"
t_false "empty golden with candidates fails (EXTRA)" stage_compare "$T/empty.tsv" "$T/same.tsv"

# stop-after
t_eq "go" "$(KIT_STOP_AFTER=5 bash -c ". '$HERE/../lib/stages.sh'; kit_stop_after 4; echo go")" "stop-after other step continues"
t_eq "" "$(KIT_STOP_AFTER=5 bash -c ". '$HERE/../lib/stages.sh'; kit_stop_after 5; echo go")" "stop-after its step exits"
t_done
