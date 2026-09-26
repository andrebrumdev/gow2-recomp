# kit/lib/stages.sh -- golden stage hashes of the kit pipeline ("Kit sem Python",
# Phase 0). Sourced by kit/setup.sh, kit/make_spu_lifts.sh, build_macos.sh and
# kit/golden/record.sh. Every capture is a no-op unless KIT_STAGE_DIR is set, so
# a default kit run is byte-for-byte unchanged.
# Record format (TSV): <stage> TAB <relpath> TAB <sha256>; '#' lines are comments.

kit_sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# stage_capture <stage> <dir> <relpath>...
stage_capture() {
    [ -n "${KIT_STAGE_DIR:-}" ] || return 0
    local stage=$1 dir=$2 f
    shift 2
    mkdir -p "$KIT_STAGE_DIR"
    for f in "$@"; do
        [ -f "$dir/$f" ] || { echo "stage_capture: missing $dir/$f" >&2; return 1; }
        printf '%s\t%s\t%s\n' "$stage" "$f" "$(kit_sha256 "$dir/$f")" >> "$KIT_STAGE_DIR/stages.tsv"
        if [ "${KIT_STAGE_KEEP:-0}" = 1 ]; then
            mkdir -p "$KIT_STAGE_DIR/$stage/$(dirname "$f")"
            cp "$dir/$f" "$KIT_STAGE_DIR/$stage/$f"
        fi
    done
}

# stage_compare <golden.tsv> <candidate.tsv> [stage]
stage_compare() {
    local golden=$1 cand=$2 only=${3:-}
    awk -F'\t' -v only="$only" -v gfile="$golden" '
        /^#/ || NF < 3 { next }
        only != "" && $1 != only { next }
        FILENAME == gfile { k = $1 "\t" $2; g[k] = $3; order[++n] = k; next }
        { k = $1 "\t" $2; if ((k in c) && c[k] != $3) dup[k] = 1; c[k] = $3 }
        END {
            bad = 0
            for (i = 1; i <= n; i++) {
                k = order[i]
                if (!(k in c))        { print "MISSING   " k; bad = 1 }
                else if (k in dup)    { print "CONFLICT  " k; bad = 1 }
                else if (c[k] != g[k]) { print "DIFF      " k; bad = 1 }
                else                    print "IDENTICAL " k
            }
            for (k in c) if (!(k in g)) { print "EXTRA     " k; bad = 1 }
            exit bad
        }' "$golden" "$cand"
}

# kit_stop_after <step>: exit 0 right after <step> when KIT_STOP_AFTER=<step>.
kit_stop_after() {
    if [ "${KIT_STOP_AFTER:-}" = "$1" ]; then
        echo "   (KIT_STOP_AFTER=$1)" >&2
        exit 0
    fi
}
