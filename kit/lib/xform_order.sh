# kit/lib/xform_order.sh -- kit/ppu_xforms/ORDER helpers (Kit sem Python, Phase 2b).
# ORDER lines: '<name>' or 'noop <name>' (Ruling 2b Q3); '#' comments and blank lines.
# Reads names and golden HASHES only -- never a lift.

# kit_order_names <ORDER>: the names, one per line, in order (noop marker dropped).
kit_order_names() {
    awk '/^[[:space:]]*#/ || /^[[:space:]]*$/ {next} {print $NF}' "$1"
}

# kit_order_noops <golden.tsv> <names_file>: the golden hash chain -- the names (in the
# names file's order) whose 8 ppu_after/<name> hashes equal the previous name's (the
# ppu_raw records for the first). rc 1 when ppu_raw or a name lacks exactly 8 records.
kit_order_noops() {
    [ -s "$2" ] || { echo "kit_order_noops: empty names file $2" >&2; return 1; }
    awk -F'\t' '
        FNR == NR { if ($0 != "") ord[++k] = $0; next }
        $1 == "ppu_raw" { prev[$2] = $3; nraw++; next }
        $1 ~ /^ppu_after\// { n = substr($1, 11); cur[n, $2] = $3; cnt[n]++ }
        END {
            if (nraw != 8) { print "golden: ppu_raw has " nraw + 0 " records (expected 8)" > "/dev/stderr"; exit 1 }
            for (i = 1; i <= k; i++) {
                n = ord[i]
                if (cnt[n] != 8) { print "golden: ppu_after/" n " has " cnt[n] + 0 " records (expected 8)" > "/dev/stderr"; exit 1 }
                same = 1
                for (f in prev) if (cur[n, f] != prev[f]) same = 0
                if (same) print n
                for (f in prev) prev[f] = cur[n, f]
            }
        }' "$2" "$1"
}
