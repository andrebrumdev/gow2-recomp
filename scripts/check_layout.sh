#!/usr/bin/env bash
# check_layout.sh -- keeps the repository root clean (fast, offline, no game data).
#
# Fails (exit 1) when:
#   (i)   a compatibility wrapper/stub at the root points to a file that is missing
#         (wrappers carry the marker line "gow2-recomp:moved-to <path>");
#   (ii)  a tracked file at the root is neither on the ROOT_KEEP allowlist below
#         nor a wrapper, or a wrapper is not listed in scripts/README.md;
#   (iii) a directory under scripts/ (or another directory created by the
#         reorganisation, see EXTRA_DIRS) is not described in scripts/README.md,
#         or has more than 5 tracked files and no README.md of its own.
#
# Usage: scripts/check_layout.sh [REPO_ROOT]       (default: the repo holding this script)
#        scripts/check_layout.sh --self-test       (proves each check can fail)
# Exit: 0 = clean, 1 = layout problem, 2 = usage/environment error.
set -uo pipefail

MARKER="gow2-recomp:moved-to"

# Entry points and project files that live at the root on purpose (see scripts/README.md,
# "What stays at the root"). Add a file here only with a reason in that section.
ROOT_KEEP="
.gitignore
.recomp.json
CLAUDE.md
LICENSE
NOTICE.md
PROMOTION_LOG.tsv
README.md
README.pt-BR.md
functions.json
build_macos.sh
env_gow2.sh
boot_macos.cpp
gow2_boot.h
gow2_overlay_provider.c
gow2_overlay_provider.h
host_gow2_f2b.c
host_gow2_factory.cpp
movie_eos_arm.c
movie_eos_arm.h
jogar_g2.sh
jogar_gow2.sh
abrir_launcher.sh
rodar_gow2.sh
rodar_gow2_intro_skip.sh
rodar_gow2_menu_fast.sh
gow2_launcher.py
make_app_bundle.sh
testar_fix.sh
apply_all_patches.sh
verify_lift.sh
verify_lift_baseline.sh
accept_relift.sh
lib_boot_chain_metrics.sh
"

# Files still waiting for their move batch (temporary; emptied by the last batch).
ROOT_PENDING="
promote_lift.sh
lib_patch_convergence.sh
test_patch_convergence.sh
smoke_relift_equiv.sh
smoke_chain_gate.sh
smoke_m0_baseline.sh
bisect_regression.sh
bisect_verdict.sh
patch_ab_sandbox.sh
test_relift_build.sh
test_relift_prepatch_link.sh
analyze_eboot_ghidra.sh
inventory_lift_markers.py
count_menu_gate.py
patch_e401_fios_done_yield_gate.py
patch_diag06_147038_revert_test.py
patch_diag08_committed_range_revert_test.py
attach_mem_mac.sh
watch_run.sh
oracle_intro_checklist.sh
decrypt_self.py
extract_pkg.py
"

# Directories outside scripts/ that the reorganisation created; each must be in scripts/README.md.
EXTRA_DIRS="notes/artifacts tools"

list_files() {   # tracked files when this is a git checkout, else every file (kit zip)
    if git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$1" ls-files
    else
        (cd "$1" && find . -type f ! -path './.git/*' | sed 's|^\./||')
    fi
}

check() {
    local R="$1" bad=0 f t d n readme
    [ -f "$R/scripts/README.md" ] || { echo "FAIL: $R/scripts/README.md missing"; return 1; }
    readme="$R/scripts/README.md"
    local files; files="$(list_files "$R")"

    # (i) + (ii): root entries
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in */*) continue ;; esac
        t="$(grep -m1 -o "$MARKER [^ ]*" "$R/$f" 2>/dev/null | awk '{print $2}')"
        if [ -n "$t" ]; then
            [ -f "$R/$t" ] || { echo "FAIL (i): wrapper $f -> $t, target missing"; bad=1; }
            grep -q -F "\`$f\`" "$readme" || { echo "FAIL (ii): wrapper $f not listed in scripts/README.md"; bad=1; }
            continue
        fi
        printf '%s\n' "$ROOT_KEEP" "$ROOT_PENDING" | grep -q -x -F "$f" \
            || { echo "FAIL (ii): root file $f is not on the allowlist (scripts/check_layout.sh ROOT_KEEP) and is not a wrapper"; bad=1; }
    done <<< "$files"

    # (iii): directories under scripts/ plus EXTRA_DIRS
    local dirs
    dirs="$( { printf '%s\n' "$files" | grep '^scripts/.*/' | sed 's|/[^/]*$||' | sort -u
               for d in $EXTRA_DIRS; do printf '%s\n' "$files" | grep -q "^$d/" && echo "$d"; done; } | sort -u)"
    # include every ancestor directory below scripts/ (scripts/archive for scripts/archive/windows/trace)
    dirs="$(printf '%s\n' "$dirs" | awk -F/ 'NF{p=$1; for(i=2;i<=NF;i++){p=p"/"$i; print p}}' | sort -u)"
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        grep -q -F "\`$d/\`" "$readme" || { echo "FAIL (iii): directory $d/ not described in scripts/README.md"; bad=1; }
        n="$(printf '%s\n' "$files" | grep -c "^$d/[^/]*$")"
        if [ "$n" -gt 5 ] && ! printf '%s\n' "$files" | grep -q -x -F "$d/README.md"; then
            echo "FAIL (iii): directory $d/ has $n files and no README.md"; bad=1
        fi
    done <<< "$dirs"
    return $bad
}

self_test() {
    local T rc=0 out
    T="$(mktemp -d)"; trap 'rm -rf "$T"' RETURN
    mkdir -p "$T/scripts/smoke"
    printf '# map\n`scripts/smoke/` smokes\n`old.sh` wrapper\n' > "$T/scripts/README.md"
    printf '#!/bin/sh\n' > "$T/scripts/smoke/new.sh"
    printf '#!/bin/sh\n# %s scripts/smoke/new.sh\n' "$MARKER" > "$T/old.sh"
    : > "$T/README.md"
    git -C "$T" init -q && git -C "$T" add -A
    check "$T" >/dev/null || { echo "self-test: clean tree reported dirty"; rc=1; }
    : > "$T/stray.sh"; git -C "$T" add stray.sh
    out="$(check "$T")"; echo "$out" | grep -q "FAIL (ii): root file stray.sh" || { echo "self-test: stray root file not caught"; rc=1; }
    git -C "$T" rm -q --cached stray.sh; rm -f "$T/stray.sh"
    git -C "$T" rm -q -f scripts/smoke/new.sh
    out="$(check "$T")"; echo "$out" | grep -q "FAIL (i): wrapper old.sh" || { echo "self-test: missing wrapper target not caught"; rc=1; }
    mkdir -p "$T/scripts/diag"; for i in 1 2 3 4 5 6; do : > "$T/scripts/diag/d$i.sh"; done; git -C "$T" add scripts/diag
    out="$(check "$T")"
    echo "$out" | grep -q "FAIL (iii): directory scripts/diag/ not described" || { echo "self-test: undocumented directory not caught"; rc=1; }
    echo "$out" | grep -q "FAIL (iii): directory scripts/diag/ has 6 files and no README.md" || { echo "self-test: missing README not caught"; rc=1; }
    [ $rc -eq 0 ] && echo "check_layout self-test: PASS" || echo "check_layout self-test: FAIL"
    return $rc
}

case "${1:-}" in
    --self-test) self_test; exit $? ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
esac
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -d "$ROOT" ] || { echo "usage: $0 [REPO_ROOT] | --self-test" >&2; exit 2; }
if check "$ROOT"; then echo "check_layout: PASS ($ROOT)"; exit 0; fi
echo "check_layout: FAIL ($ROOT)"; exit 1
