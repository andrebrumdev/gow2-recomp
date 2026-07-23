#!/usr/bin/env python3
"""R5 — enter probes for func_00017ACC + static callers (pre vs post R_Perm).

Context
-------
Only flip issuer pre-WAD is the func_00017ACC band (guest EA 0x17ADE/0x17ADF).
Zero SetFlip after R_LglScA open. This probe answers: who calls 17ACC, and does
any enter happen AFTER R_PermA full (g_ps3_rperma_full)?

Targets (static direct callers in recomp_macos_v2):
  000.cpp: func_0001E1A8, func_0001E34C, func_0001EAD8, func_00025064, func_00025614
  001.cpp: func_0001E3DC, func_0001E3E8, func_0001E400, func_0001E4AC
  + func_00017ACC itself

Gate (default OFF) — M1 disc contract:
  PS3_TRACE_17ACC=1  → ON only if first char is '1'
  unset / empty / '0' / 'false' / anything else → OFF (no-op baseline)

Telemetry
---------
Shared counters (defined in 000, used by 001 via extern):
  g_ps3_17acc_tot[id]  — all enters
  g_ps3_17acc_post[id] — enters while g_ps3_rperma_full != 0
post_rperm uses the existing movie_hle flag (set on R_PermA full) — no new
runtime mark required.

Log format (capped):
  [17ACC] enter fn=17ACC tot=N post=M r3=0x.. r4=0x..
  first 8 of 17ACC, first 4 of each caller; summary every 10000 grand or atexit.

Idempotent: MARKER present → ALREADY. Region-scoped: inject right after each
`void func_... {` signature line. Does not alter guest control flow when OFF.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "17ACC-PROBE"
LOG_TAG = "[17ACC] enter"

# (short name, function symbol, cpp chunk key, log cap)
SITES = [
    ("17ACC", "func_00017ACC", "000", 8),
    ("1E1A8", "func_0001E1A8", "000", 4),
    ("1E34C", "func_0001E34C", "000", 4),
    ("1EAD8", "func_0001EAD8", "000", 4),
    ("25064", "func_00025064", "000", 4),
    ("25614", "func_00025614", "000", 4),
    ("1E3DC", "func_0001E3DC", "001", 4),
    ("1E3E8", "func_0001E3E8", "001", 4),
    ("1E400", "func_0001E400", "001", 4),
    ("1E4AC", "func_0001E4AC", "001", 4),
]

HELPER_BLOCK = r'''
/* 17ACC-PROBE: R5 enter counters pre vs post R_Perm (PS3_TRACE_17ACC=1) */
#include <signal.h>
extern "C" volatile int g_ps3_rperma_full;
enum { PS3_17ACC_FN_N = 10 };
static const char* const g_ps3_17acc_fn_name[PS3_17ACC_FN_N] = {
    "17ACC","1E1A8","1E34C","1EAD8","25064","25614","1E3DC","1E3E8","1E400","1E4AC"
};
static const int g_ps3_17acc_log_cap[PS3_17ACC_FN_N] = {
    8,4,4,4,4,4,4,4,4,4
};
unsigned long long g_ps3_17acc_tot[PS3_17ACC_FN_N];
unsigned long long g_ps3_17acc_post[PS3_17ACC_FN_N];
unsigned long long g_ps3_17acc_grand;
static int g_ps3_17acc_atexit_reg = 0;
static int g_ps3_17acc_gate = -1;

static int ps3_17acc_gate_on(void) {
    if (g_ps3_17acc_gate < 0) {
        extern char* getenv(const char*);
        const char* e = getenv("PS3_TRACE_17ACC");
        /* M1 disc contract: ON only if first char is '1'. */
        g_ps3_17acc_gate = (e && *e == '1') ? 1 : 0;
    }
    return g_ps3_17acc_gate;
}

static void ps3_17acc_dump_summary(void) {
    if (!ps3_17acc_gate_on()) return;
    fprintf(stderr, "[17ACC] SUMMARY grand=%llu rperma_full=%d\n",
            (unsigned long long)g_ps3_17acc_grand, (int)g_ps3_rperma_full);
    for (int i = 0; i < PS3_17ACC_FN_N; i++) {
        unsigned long long t = g_ps3_17acc_tot[i];
        unsigned long long p = g_ps3_17acc_post[i];
        /* Always print every site so tot=0 is visible. */
        fprintf(stderr,
                "[17ACC] SUMMARY fn=%s tot=%llu post=%llu pre=%llu\n",
                g_ps3_17acc_fn_name[i],
                (unsigned long long)t,
                (unsigned long long)p,
                (unsigned long long)(t >= p ? t - p : 0));
    }
    fflush(stderr);
}

static void ps3_17acc_on_sigterm(int sig) {
    (void)sig;
    ps3_17acc_dump_summary();
}

#if defined(__GNUC__) || defined(__clang__)
__attribute__((constructor))
#endif
static void ps3_17acc_ctor(void) {
    if (!ps3_17acc_gate_on()) return;
    fprintf(stderr, "[17ACC] probe armed (post=g_ps3_rperma_full)\n");
    fflush(stderr);
    if (!g_ps3_17acc_atexit_reg) {
        g_ps3_17acc_atexit_reg = 1;
        atexit(ps3_17acc_dump_summary);
#ifndef _WIN32
        signal(SIGTERM, ps3_17acc_on_sigterm);
#endif
    }
}

void ps3_17acc_on_enter(int id, ppu_context* ctx) {
    if (!ps3_17acc_gate_on()) return;
    if (id < 0 || id >= PS3_17ACC_FN_N || !ctx) return;
    if (!g_ps3_17acc_atexit_reg) {
        g_ps3_17acc_atexit_reg = 1;
        atexit(ps3_17acc_dump_summary);
    }
    unsigned long long t = ++g_ps3_17acc_tot[id];
    unsigned long long p = g_ps3_17acc_post[id];
    if (g_ps3_rperma_full) p = ++g_ps3_17acc_post[id];
    unsigned long long g = ++g_ps3_17acc_grand;
    int cap = g_ps3_17acc_log_cap[id];
    int do_log = (t <= (unsigned long long)cap) || ((g % 10000ull) == 0);
    if (do_log) {
        fprintf(stderr,
                "[17ACC] enter fn=%s tot=%llu post=%llu r3=0x%08X r4=0x%08X\n",
                g_ps3_17acc_fn_name[id],
                (unsigned long long)t,
                (unsigned long long)p,
                (unsigned)(uint32_t)ctx->gpr[3],
                (unsigned)(uint32_t)ctx->gpr[4]);
        fflush(stderr);
    }
    if ((g % 10000ull) == 0) ps3_17acc_dump_summary();
}
/* 17ACC-PROBE end helpers */
'''

EXTERN_DECL = (
    "/* 17ACC-PROBE extern (defs in ppu_recomp_000.cpp) */\n"
    "void ps3_17acc_on_enter(int id, ppu_context* ctx);\n"
)


def inject_call(body_start: str, site_id: int) -> str:
    """Insert probe call immediately after opening brace line of function."""
    # body_start is "void func_...(ppu_context* ctx) {\n"
    call = (
        f"        /* {MARKER} id={site_id} */\n"
        f"        {{ ps3_17acc_on_enter({site_id}, ctx); }}\n"
    )
    return body_start + call


def patch_file(path: Path, chunk: str) -> str:
    t = path.read_text(encoding="utf-8", errors="replace")
    orig = t

    if chunk == "000":
        if "/* 17ACC-PROBE: R5 enter counters" not in t:
            # After last early include / extern block near top: insert after
            # the type15 disc counter if present, else after stdlib include.
            anchor = "static int g_ps3_type15_disc_n = 0;\n"
            if anchor in t:
                t = t.replace(anchor, anchor + HELPER_BLOCK, 1)
            else:
                alt = "#include <stdlib.h>\n"
                if alt not in t:
                    raise SystemExit(f"{path}: no place for helper block")
                t = t.replace(alt, alt + HELPER_BLOCK, 1)
            print(f"  helpers: added to {path.name}")
        else:
            print(f"  helpers: already in {path.name}")
    elif chunk == "001":
        if "/* 17ACC-PROBE extern" not in t:
            # After includes: first function-ish extern or after stdlib
            alt = "#include <stdlib.h>\n"
            if alt in t:
                t = t.replace(alt, alt + EXTERN_DECL, 1)
            else:
                # fall back: after ppu_recomp.h
                h = '#include "ppu_recomp.h"\n'
                if h not in t:
                    raise SystemExit(f"{path}: no place for extern decl")
                t = t.replace(h, h + EXTERN_DECL, 1)
            print(f"  extern: added to {path.name}")
        else:
            print(f"  extern: already in {path.name}")

    for site_id, (short, fn, fn_chunk, _cap) in enumerate(SITES):
        if fn_chunk != chunk:
            continue
        sig = f"void {fn}(ppu_context* ctx) {{\n"
        if sig not in t:
            raise SystemExit(f"{path}: missing signature for {fn}")
        # Already injected?
        probe_line = f"        /* {MARKER} id={site_id} */\n"
        # Find function start and check region
        idx = t.find(sig)
        if idx < 0:
            raise SystemExit(f"{path}: {fn} sig vanished")
        # Only one definition expected
        if t.count(sig) != 1:
            raise SystemExit(f"{path}: {fn} signature count={t.count(sig)}")
        region_start = idx + len(sig)
        # peek ahead: already has probe?
        ahead = t[region_start : region_start + 120]
        if probe_line in ahead or f"ps3_17acc_on_enter({site_id}," in ahead:
            print(f"  {fn} ({short}): ALREADY")
            continue
        t = t[:region_start] + inject_call("", site_id) + t[region_start:]
        # inject_call with empty body_start just returns the call lines
        print(f"  {fn} ({short}): APPLIED id={site_id}")

    if t == orig:
        return t
    # Prefer newline="\n" (Py>=3.10) to avoid CRLF on Windows hosts; fall back.
    try:
        path.write_text(t, encoding="utf-8", newline="\n")
    except TypeError:
        path.write_text(t, encoding="utf-8")
    return t


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        Path(__file__).resolve().parent.parent / "recomp_macos_v2"
    )
    if not root.is_dir():
        print(f"lift dir missing: {root}", file=sys.stderr)
        return 2

    files = {
        "000": root / "ppu_recomp_000.cpp",
        "001": root / "ppu_recomp_001.cpp",
    }
    rc = 0
    for chunk, path in files.items():
        if not path.exists():
            print(f"skip missing {path}")
            rc = 1
            continue
        print(f"== {path.name} ==")
        try:
            before = path.read_text(encoding="utf-8", errors="replace")
            after = patch_file(path, chunk)
            if after == before and MARKER in before:
                print(f"ALREADY-APPLIED {path}")
            elif after != before or MARKER in after:
                # re-read to detect write
                now = path.read_text(encoding="utf-8", errors="replace")
                if MARKER not in now and LOG_TAG.replace(" enter", "") not in now:
                    # helpers use MARKER string
                    if "17ACC-PROBE" not in now:
                        print(f"FAILED {path}: marker missing after patch")
                        rc = 1
                    else:
                        print(f"APPLIED {path}")
                else:
                    print(f"APPLIED/OK {path}")
            else:
                print(f"UNCHANGED {path} (unexpected)")
                rc = 1
        except SystemExit as e:
            print(f"FAILED {path}: {e}")
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
