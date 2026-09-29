#!/usr/bin/env bash
# kit/golden/per_patch_check.sh -- internal consistency of the per-patch golden
# (Kit sem Python, Phase 2a).
#
#   kit/golden/per_patch_check.sh [golden.tsv] [status.tsv]
#
#     golden.tsv  (default: stages.tsv next to it) -- HASHES ONLY. This is the file
#                 record.sh --write copies verbatim into the committed
#                 kit/golden/stages.tsv, so it never contains a status word
#                 (Codex review BLOCKER, 2026-09-28; Controller ruling 1).
#     status.tsv  optional -- the scratch $KIT_STAGE_DIR/ppu_status.tsv a record.sh run
#                 leaves on disk (Task 1's stage_record; never committed, gone once the
#                 scratch dir is cleaned up).
#
# Hash-only mode (status.tsv omitted -- what kit/tests/run_all.sh and CI run against
# the committed golden): every ppu_after/<patch>, ppu_raw, ppu_patched and
# ppu_after/kit_delta has the 8 PPU files; ppu_after/kit_delta == ppu_final.
#
# Full mode (+ status.tsv, used right after a record.sh run, Task 5): also -- order
# fields 001..N contiguous and unique; every status is a known one; APPLIED /
# FAILED-PARTIAL change >= 1 file versus the previous snapshot in that order (ppu_raw
# before patch 001), every other status changes none; the last snapshot in order =
# ppu_patched; status.tsv and golden.tsv name the exact same set of ppu_after/<patch>
# stages (two halves of the same recording run -- they must never drift apart).
#
# rc 0: one "PER-PATCH OK ..." line. rc 1: "PER-PATCH BAD: ..." lines (one or more).
# rc 2: golden.tsv, or a given status.tsv, does not exist.
set -euo pipefail
G="${1:-$(cd "$(dirname "$0")" && pwd)/stages.tsv}"
ST="${2:-}"
[ -f "$G" ] || { echo "PER-PATCH BAD: no golden at $G" >&2; exit 2; }
[ -z "$ST" ] || [ -f "$ST" ] || { echo "PER-PATCH BAD: no status file at $ST" >&2; exit 2; }
awk -F'\t' -v STATUS_FILE="$ST" '
    function bad(m) { print "PER-PATCH BAD: " m; nbad++ }
    function full(s,   i) { for (i = 1; i <= nf; i++) if (!((s SUBSEP F[i]) in h)) return 0; return 1 }
    function same(a, b,   i) { for (i = 1; i <= nf; i++) if (h[a SUBSEP F[i]] != h[b SUBSEP F[i]]) return 0; return 1 }
    BEGIN {
        nf = split("ppu_recomp.h ppu_recomp_000.cpp ppu_recomp_001.cpp ppu_recomp_002.cpp ppu_recomp_003.cpp ppu_recomp_004.cpp ppu_recomp_005.cpp ppu_recomp_006.cpp", F, " ")
        ns = split("APPLIED ALREADY-APPLIED NO-MATCH UNVERIFIED FAILED FAILED-PARTIAL SKIPPED", S, " ")
        for (i = 1; i <= ns; i++) known[S[i]] = 1
        if (STATUS_FILE != "") {
            while ((getline line < STATUS_FILE) > 0) {
                n_f = split(line, fd, "\t")
                if (n_f < 3 || fd[1] != "ppu_status") continue
                c = index(fd[3], ":"); ord = substr(fd[3], 1, c - 1); st = substr(fd[3], c + 1)
                if (c == 0 || ord !~ /^[0-9][0-9][0-9]$/ || ord + 0 < 1) { bad("bad order field " fd[3] " for " fd[2]); continue }
                idx = ord + 0
                if (idx in name) bad("order " ord " used twice (" name[idx] ", " fd[2] ")")
                name[idx] = fd[2]; status[idx] = st; seen_patch[fd[2]] = 1; if (idx > n) n = idx
                if (!(st in known)) bad("unknown status " st " for " fd[2])
            }
            close(STATUS_FILE)
        }
    }
    /^#/ || NF < 3 { next }
    { h[$1 SUBSEP $2] = $3 }
    $1 ~ /^ppu_after\// && $1 != "ppu_after/kit_delta" { gname[substr($1, 11)] = 1 }
    END {
        if (!full("ppu_raw")) bad("ppu_raw does not have the 8 PPU files")
        if (!full("ppu_patched")) bad("ppu_patched does not have the 8 PPU files")
        if (!full("ppu_after/kit_delta") || !full("ppu_final") || !same("ppu_after/kit_delta", "ppu_final")) bad("ppu_after/kit_delta != ppu_final")

        if (STATUS_FILE == "") {
            gcount = 0
            for (nm in gname) { gcount++; if (!full("ppu_after/" nm)) bad("ppu_after/" nm " does not have the 8 PPU files") }
            if (gcount == 0) bad("no ppu_after/<patch> records")
            if (nbad) exit 1
            kd = 0
            for (i = 1; i <= nf; i++) if (h["ppu_patched" SUBSEP F[i]] != h["ppu_after/kit_delta" SUBSEP F[i]]) kd++
            print "PER-PATCH OK (hashes only) n=" gcount " kit_delta_files=" kd
            exit 0
        }

        if (n == 0) { bad("no ppu_status records in " STATUS_FILE); exit 1 }
        for (nm in gname) if (!(nm in seen_patch)) bad("ppu_after/" nm " in the golden has no ppu_status record in " STATUS_FILE)
        for (idx in name) if (!(name[idx] in gname)) bad(name[idx] " has a ppu_status record but no ppu_after/" name[idx] " in the golden")

        prev = "ppu_raw"
        for (i = 1; i <= n; i++) {
            if (!(i in name)) { bad("order gap at " sprintf("%03d", i)); continue }
            s = "ppu_after/" name[i]
            if (!full(s)) { bad(s " does not have the 8 PPU files"); prev = s; continue }
            changed = !same(prev, s)
            writes = (status[i] == "APPLIED" || status[i] == "FAILED-PARTIAL")
            if (writes && !changed) bad(name[i] " is " status[i] " but changed no file")
            if (!writes && changed) bad(name[i] " is " status[i] " but changed a file")
            cnt[status[i]]++
            prev = s
        }
        if (!same(prev, "ppu_patched")) bad("last snapshot (" prev ") != ppu_patched")
        if (nbad) exit 1
        line = "PER-PATCH OK n=" n
        for (k = 1; k <= ns; k++) if (S[k] in cnt) line = line " " S[k] "=" cnt[S[k]]
        kd = 0
        for (i = 1; i <= nf; i++) if (h[prev SUBSEP F[i]] != h["ppu_after/kit_delta" SUBSEP F[i]]) kd++
        print line " kit_delta_files=" kd
    }' "$G"
