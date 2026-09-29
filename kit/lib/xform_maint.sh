# kit/lib/xform_maint.sh -- guards shared by the Phase-2 maintainer drivers
# (kit/golden/xform_check.sh, kit/golden/xform_convert.sh). What they write is lifted code
# (before-states, diffs, drafts): it may only live in a scratch dir outside every git work
# tree (the user's playing tree is one), and only the pinned raw lift is a valid input.
# Needs kit/lib/stages.sh (kit_sha256) sourced first.
KIT_PPU_FILES="ppu_recomp.h ppu_recomp_000.cpp ppu_recomp_001.cpp ppu_recomp_002.cpp ppu_recomp_003.cpp ppu_recomp_004.cpp ppu_recomp_005.cpp ppu_recomp_006.cpp"

# kit_scratch_dir <path> <marker>: create/reuse a scratch dir; print its physical path.
kit_scratch_dir() {
    local s=$1 mark=$2 a p
    case "$s" in /*) ;; *) s="$PWD/$s" ;; esac
    case "$s/" in */./*|*/../*) echo "scratch $1: a '.' or '..' component -- refused" >&2; return 2 ;; esac
    a=$s; while [ ! -d "$a" ]; do a=${a%/*}; [ -n "$a" ] || a=/; done
    if git -C "$a" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "scratch $1: inside a git work tree -- refused (lifted code)" >&2; return 2
    fi
    if [ -d "$s" ] && [ ! -f "$s/$mark" ] && [ -n "$(ls -A "$s")" ]; then
        echo "scratch $1: not empty and not created by this tool (no $mark) -- refused" >&2; return 2
    fi
    mkdir -p "$s" || return 2
    p="$(cd "$s" && pwd -P)" || return 2
    if git -C "$p" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "scratch $1: inside a git work tree -- refused (lifted code)" >&2; return 2
    fi
    : > "$p/$mark"
    printf '%s\n' "$p"
}

# kit_check_raw <raw_dir> <golden.tsv>: rc 0 iff the 8 files are the golden's ppu_raw.
kit_check_raw() {
    local raw=$1 golden=$2 f want got bad=0
    for f in $KIT_PPU_FILES; do
        want="$(awk -F'\t' -v f="$f" '$1=="ppu_raw" && $2==f {print $3}' "$golden")"
        got=""; [ -f "$raw/$f" ] && got="$(kit_sha256 "$raw/$f")"
        if [ -z "$want" ] || [ "$want" != "$got" ]; then echo "raw lift: $f is not the golden's ppu_raw" >&2; bad=1; fi
    done
    return $bad
}

# kit_xform_fragments <xform> <patch_script>: the FRAGMENT REVIEW GATE's input -- one row
# per authored fragment of ANY length: "<stem>.xform:<line> TAB <status> TAB <fragment>".
# Fragments: each template line split at {{line}}, each subst split at {{line}} and \1..\9,
# each regex whole; trimmed; empty ones dropped. Status: IN-SCRIPT:<script lines (max 3)>,
# NOT-IN-SCRIPT, or POSITIONAL (a regex made only of ([\s\S]{n}) groups: no text).
# IN-SCRIPT is a hint, not a verdict: the reviewer still checks the script line WRITES the
# text (inserted block / replacement) and is not the script's needle (lifted text).
kit_xform_fragments() {
    local x=$1 script=$2 ref kind frag lines st
    awk -v f="$(basename "$x")" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function emit(s, re,   n, i, parts, p) { n = split(s, parts, re)
            for (i = 1; i <= n; i++) { p = trim(parts[i]); if (p != "") print f ":" NR "\tT\t" p } }
        intmpl && $0 == tag { intmpl = 0; next }
        intmpl { emit($0, "[{][{]line[}][}]"); next }
        /^template <</ { tag = substr($0, 12); intmpl = 1; next }
        /^subst / { emit(substr($0, 7), "[{][{]line[}][}]|\\\\[1-9]"); next }
        /^regex / { r = substr($0, 7); t = r; gsub(/[(][[]\\s\\S[]][{][0-9]+[}][)]/, "", t)
                    if (t == "^$") print f ":" NR "\tP\t-"; else if (trim(r) != "") print f ":" NR "\tT\t" trim(r); next }
    ' "$x" | while IFS="$(printf '\t')" read -r ref kind frag; do
        if [ "$kind" = P ]; then printf '%s\tPOSITIONAL\t-\n' "$ref"; continue; fi
        lines="$(grep -nF -- "$frag" "$script" | cut -d: -f1 | head -3 | paste -sd, -)"
        if [ -n "$lines" ]; then st="IN-SCRIPT:$lines"; else st=NOT-IN-SCRIPT; fi
        printf '%s\t%s\t%s\n' "$ref" "$st" "$frag"
    done
}
