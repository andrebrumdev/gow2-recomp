#!/usr/bin/env python3
"""SHADERSRC loop probes (2026-07-22): what happens after N>0.

func_003CC208 (ppu_recomp_001.cpp) reads N then either early-exits or loops
over records: stream-read key → parse helpers → insert via func_003C8578.

With HOSTRES fixed, N sum≈889 natural. This patch measures whether the loop
*runs* and *inserts*, vs bailing on capacity/size gates — without forging CRC
or registry.

Gated by PS3_TRACE_SHADERSRC (fallback PS3_TRACE_TYMAP). OFF default.
Idempotent marker SS-LOOP. Read-only.
"""
from pathlib import Path
import sys

MARKER = "SS-LOOP"

ROOT = (Path(sys.argv[1]) if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "recomp_macos_v2")
C1 = ROOT / "ppu_recomp_001.cpp"

s = C1.read_text(encoding="utf-8", errors="replace")
changed = False

PROBE_ON = (
    '{ static int on=-1; if(on<0){extern char* getenv(const char*);\n'
    '            const char* e=getenv("PS3_TRACE_SHADERSRC"); '
    'const char* e2=getenv("PS3_TRACE_TYMAP");\n'
    '            on=((e&&*e&&*e!=\'0\')||(e2&&*e2&&*e2!=\'0\'))?1:0;}\n'
)


def add(label, old, new):
    global s, changed
    if f"[{label}]" in s:
        print(f"{label}: already present")
        return
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"{label}: needle count={n} (expected 1)")
    s = s.replace(old, new, 1)
    changed = True
    print(f"{label}: added")


# --- early exit: N too large (cmp vs 0x4EC4, GT → 003CC4BC) ---
add(
    "SS-BIG",
    "        if (((ctx->cr >> 0) & 4)) { g_trampoline_fn = (void(*)(void*))func_003CC4BC; return; }\n"
    "        ctx->gpr[11] = vm_read32(ctx->gpr[30] + 0x4);\n",
    f"        /* {MARKER} */\n"
    f"        {PROBE_ON}"
    "          if(on && ((ctx->cr >> 0) & 4)){ static int n=0; if(n++<16)\n"
    "            fprintf(stderr,\"[SS-BIG] #%d N=%d obj=0x%08X (N>0x4EC4)\\n\",\n"
    "              n,(int32_t)ctx->gpr[25],(uint32_t)ctx->gpr[26]); fflush(stderr);} }\n"
    "        if (((ctx->cr >> 0) & 4)) { g_trampoline_fn = (void(*)(void*))func_003CC4BC; return; }\n"
    "        ctx->gpr[11] = vm_read32(ctx->gpr[30] + 0x4);\n",
)

# --- early exit: capacity / grow fail → 003CC3F4 ---
add(
    "SS-CAP",
    "        if (((ctx->cr >> 0) & 8)) { g_trampoline_fn = (void(*)(void*))func_003CC3F4; return; }\n"
    "        { int64_t a = (int32_t)ctx->gpr[25]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }\n",
    f"        /* {MARKER} */\n"
    f"        {PROBE_ON}"
    "          if(on && ((ctx->cr >> 0) & 8)){ static int n=0; if(n++<16)\n"
    "            fprintf(stderr,\"[SS-CAP] #%d N=%d obj=0x%08X (capacity LT)\\n\",\n"
    "              n,(int32_t)ctx->gpr[25],(uint32_t)ctx->gpr[26]); fflush(stderr);} }\n"
    "        if (((ctx->cr >> 0) & 8)) { g_trampoline_fn = (void(*)(void*))func_003CC3F4; return; }\n"
    "        { int64_t a = (int32_t)ctx->gpr[25]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }\n",
)

# --- N<=0 skip loop ---
add(
    "SS-EMPTY",
    "        if ((!((ctx->cr >> 0) & 4))) goto loc_003CC3B8;\n"
    "        ctx->gpr[28] = (int64_t)(int32_t)(0);\n",
    f"        /* {MARKER} */\n"
    f"        {PROBE_ON}"
    "          if(on && (!((ctx->cr >> 0) & 4))){ static int n=0; if(n++<32)\n"
    "            fprintf(stderr,\"[SS-EMPTY] #%d N=%d obj=0x%08X skip-loop\\n\",\n"
    "              n,(int32_t)ctx->gpr[25],(uint32_t)ctx->gpr[26]); fflush(stderr);} }\n"
    "        if ((!((ctx->cr >> 0) & 4))) goto loc_003CC3B8;\n"
    "        ctx->gpr[28] = (int64_t)(int32_t)(0);\n",
)

# --- record key after first stream read in loop ---
add(
    "SS-REC",
    "        func_001856A8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    "        /* nop */;\n"
    "        ctx->gpr[0] = vm_read32(ctx->gpr[1] + 0x70);\n"
    "        ctx->gpr[3] = ctx->gpr[22] | ctx->gpr[22];\n"
    "        ctx->gpr[4] = ctx->gpr[27] | ctx->gpr[27];\n"
    "        vm_write32(ctx->gpr[1] + 0xB0, ctx->gpr[0]);\n"
    "        func_003CBB98(ctx); DRAIN_TRAMPOLINE(ctx);\n",
    "        func_001856A8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    "        /* nop */;\n"
    "        ctx->gpr[0] = vm_read32(ctx->gpr[1] + 0x70);\n"
    "        ctx->gpr[3] = ctx->gpr[22] | ctx->gpr[22];\n"
    "        ctx->gpr[4] = ctx->gpr[27] | ctx->gpr[27];\n"
    "        vm_write32(ctx->gpr[1] + 0xB0, ctx->gpr[0]);\n"
    f"        /* {MARKER}: record key */\n"
    f"        {PROBE_ON}"
    "          if(on){ static int n=0; if(n++<48)\n"
    "            fprintf(stderr,\"[SS-REC] #%d i=%d key=0x%08X N=%d obj=0x%08X\\n\",\n"
    "              n,(int32_t)ctx->gpr[28],(uint32_t)ctx->gpr[0],\n"
    "              (int32_t)ctx->gpr[25],(uint32_t)ctx->gpr[26]); fflush(stderr);} }\n"
    "        func_003CBB98(ctx); DRAIN_TRAMPOLINE(ctx);\n",
)

# --- insert path ---
add(
    "SS-INS",
    "        ctx->gpr[28] = (int64_t)(int32_t)(ctx->gpr[28] + 1);\n"
    "        func_003C8578(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    "        /* nop */;\n"
    "        ctx->gpr[3] = ctx->gpr[31] | ctx->gpr[31];\n"
    "        func_0015DB48(ctx); DRAIN_TRAMPOLINE(ctx);\n",
    "        ctx->gpr[28] = (int64_t)(int32_t)(ctx->gpr[28] + 1);\n"
    f"        /* {MARKER}: insert */\n"
    f"        {PROBE_ON}"
    "          if(on){ static int n=0; static int tot=0; tot++;\n"
    "            if(n++<32 || (tot%100)==0)\n"
    "            fprintf(stderr,\"[SS-INS] #%d tot=%d i=%d key@b0=0x%08X N=%d\\n\",\n"
    "              n,tot,(int32_t)ctx->gpr[28],\n"
    "              vm_read32(ctx->gpr[1]+0xB0),(int32_t)ctx->gpr[25]); fflush(stderr);} }\n"
    "        func_003C8578(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    "        /* nop */;\n"
    "        ctx->gpr[3] = ctx->gpr[31] | ctx->gpr[31];\n"
    "        func_0015DB48(ctx); DRAIN_TRAMPOLINE(ctx);\n",
)

# --- DONE on normal epilogue (only the one in 003CC208: restore after loc_003CC3B8) ---
# The epilogue starts at loc_003CC3B8. There may be similar patterns elsewhere;
# anchor with the unique stack restore size 0x150 of this function.
add(
    "SS-DONE",
    "loc_003CC3B8:\n"
    "        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x160);\n"
    "        ctx->gpr[21] = vm_read64(ctx->gpr[1] + 0xF8);\n"
    "        ctx->gpr[22] = vm_read64(ctx->gpr[1] + 0x100);\n",
    "loc_003CC3B8:\n"
    f"        /* {MARKER}: loop done */\n"
    f"        {PROBE_ON}"
    "          if(on){ static int n=0; if(n++<32)\n"
    "            fprintf(stderr,\"[SS-DONE] #%d i=%d N=%d obj=0x%08X\\n\",\n"
    "              n,(int32_t)ctx->gpr[28],(int32_t)ctx->gpr[25],\n"
    "              (uint32_t)ctx->gpr[26]); fflush(stderr);} }\n"
    "        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x160);\n"
    "        ctx->gpr[21] = vm_read64(ctx->gpr[1] + 0xF8);\n"
    "        ctx->gpr[22] = vm_read64(ctx->gpr[1] + 0x100);\n",
)

# --- entry of insert helper (global count, may be called from elsewhere) ---
C1_ok = True
if "[SS-INSFN]" not in s:
    old = (
        "void func_003C8578(ppu_context* ctx) {\n"
        "        vm_write64(ctx->gpr[1] + -0x140, ctx->gpr[1]); ctx->gpr[1] += -0x140;\n"
    )
    new = (
        "void func_003C8578(ppu_context* ctx) {\n"
        f"        /* {MARKER}: insert helper entry */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<24 || (n%200)==0)\n"
        "            fprintf(stderr,\"[SS-INSFN] #%d tbl=0x%08X flag=%d rec=0x%08X\\n\",\n"
        "              n,(uint32_t)ctx->gpr[3],(int32_t)ctx->gpr[5],\n"
        "              (uint32_t)ctx->gpr[6]); fflush(stderr);} }\n"
        "        vm_write64(ctx->gpr[1] + -0x140, ctx->gpr[1]); ctx->gpr[1] += -0x140;\n"
    )
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"SS-INSFN needle count={n}")
    s = s.replace(old, new, 1)
    changed = True
    print("SS-INSFN: added")
else:
    print("SS-INSFN: already present")

if changed:
    C1.write_text(s, encoding="utf-8", newline="\n")
    print("OK wrote ppu_recomp_001.cpp")
else:
    print("001 unchanged")

# --- Grow path resume lives in a LIFTER SPLIT fragment func_003CC2B8 (005),
# not in 003CC208 body. After SS-CAP → 003CC3F4 grow, trampoline lands here. ---
C5 = ROOT / "ppu_recomp_005.cpp"
s5 = C5.read_text(encoding="utf-8", errors="replace")
ch5 = False

if "[SS-RESUME]" not in s5:
    old = (
        "void func_003CC2B8(ppu_context* ctx) {\n"
        "        { int64_t a = (int32_t)ctx->gpr[25]; int64_t b = (int64_t)0; "
        "uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; "
        "ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }\n"
    )
    new = (
        "void func_003CC2B8(ppu_context* ctx) {\n"
        f"        /* {MARKER}: post-grow resume */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<32)\n"
        "            fprintf(stderr,\"[SS-RESUME] #%d N=%d obj=0x%08X base=0x%08X\\n\",\n"
        "              n,(int32_t)ctx->gpr[25],(uint32_t)ctx->gpr[26],\n"
        "              (uint32_t)vm_read32(ctx->gpr[26]+0x4)); fflush(stderr);} }\n"
        "        { int64_t a = (int32_t)ctx->gpr[25]; int64_t b = (int64_t)0; "
        "uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; "
        "ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }\n"
    )
    n = s5.count(old)
    if n != 1:
        raise SystemExit(f"SS-RESUME needle count={n}")
    s5 = s5.replace(old, new, 1)
    ch5 = True
    print("SS-RESUME: added")
else:
    print("SS-RESUME: already present")

if "[SS-REC2]" not in s5:
    old = (
        "        func_001856A8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
        "        /* nop */;\n"
        "        ctx->gpr[0] = vm_read32(ctx->gpr[1] + 0x70);\n"
        "        ctx->gpr[3] = ctx->gpr[22] | ctx->gpr[22];\n"
        "        ctx->gpr[4] = ctx->gpr[27] | ctx->gpr[27];\n"
        "        vm_write32(ctx->gpr[1] + 0xB0, ctx->gpr[0]);\n"
        "        func_003CBB98(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    # may appear only once in 005 inside 003CC2B8; verify
    n = s5.count(old)
    if n != 1:
        raise SystemExit(f"SS-REC2 needle count={n} in 005")
    new = (
        "        func_001856A8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
        "        /* nop */;\n"
        "        ctx->gpr[0] = vm_read32(ctx->gpr[1] + 0x70);\n"
        "        ctx->gpr[3] = ctx->gpr[22] | ctx->gpr[22];\n"
        "        ctx->gpr[4] = ctx->gpr[27] | ctx->gpr[27];\n"
        "        vm_write32(ctx->gpr[1] + 0xB0, ctx->gpr[0]);\n"
        f"        /* {MARKER}: rec on resume fragment */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<48)\n"
        "            fprintf(stderr,\"[SS-REC2] #%d i=%d key=0x%08X N=%d\\n\",\n"
        "              n,(int32_t)ctx->gpr[28],(uint32_t)ctx->gpr[0],\n"
        "              (int32_t)ctx->gpr[25]); fflush(stderr);} }\n"
        "        func_003CBB98(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    s5 = s5.replace(old, new, 1)
    ch5 = True
    print("SS-REC2: added")
else:
    print("SS-REC2: already present")

if "[SS-INS2]" not in s5:
    old = (
        "        ctx->gpr[28] = (int64_t)(int32_t)(ctx->gpr[28] + 1);\n"
        "        func_003C8578(ctx); DRAIN_TRAMPOLINE(ctx);\n"
        "        /* nop */;\n"
        "        ctx->gpr[3] = ctx->gpr[31] | ctx->gpr[31];\n"
        "        func_0015DB48(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    n = s5.count(old)
    if n != 1:
        raise SystemExit(f"SS-INS2 needle count={n} in 005")
    new = (
        "        ctx->gpr[28] = (int64_t)(int32_t)(ctx->gpr[28] + 1);\n"
        f"        /* {MARKER}: insert on resume fragment */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; static int tot=0; tot++;\n"
        "            if(n++<32 || (tot%100)==0)\n"
        "            fprintf(stderr,\"[SS-INS2] #%d tot=%d i=%d key=0x%08X N=%d\\n\",\n"
        "              n,tot,(int32_t)ctx->gpr[28],\n"
        "              vm_read32(ctx->gpr[1]+0xB0),(int32_t)ctx->gpr[25]); fflush(stderr);} }\n"
        "        func_003C8578(ctx); DRAIN_TRAMPOLINE(ctx);\n"
        "        /* nop */;\n"
        "        ctx->gpr[3] = ctx->gpr[31] | ctx->gpr[31];\n"
        "        func_0015DB48(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    s5 = s5.replace(old, new, 1)
    ch5 = True
    print("SS-INS2: added")
else:
    print("SS-INS2: already present")

# DONE on resume fragment epilogue — loc_003CC3B8 only as goto target then return
if "[SS-DONE2]" not in s5:
    # find epilogue of 003CC2B8: after loop exit, restore stack 0x150
    i = s5.find("void func_003CC2B8")
    j = s5.find("\nvoid func_", i + 20)
    region = s5[i:j]
    old = (
        "loc_003CC3B8:\n"
        "        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x160);\n"
        "        ctx->gpr[21] = vm_read64(ctx->gpr[1] + 0xF8);\n"
        "        ctx->gpr[22] = vm_read64(ctx->gpr[1] + 0x100);\n"
    )
    if old not in region:
        # maybe different shape — search
        print("SS-DONE2: epilogue needle missing in 003CC2B8; dump tail:")
        print(region[-800:])
        raise SystemExit("SS-DONE2 needle missing")
    new = (
        "loc_003CC3B8:\n"
        f"        /* {MARKER}: done on resume fragment */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<32)\n"
        "            fprintf(stderr,\"[SS-DONE2] #%d i=%d N=%d obj=0x%08X\\n\",\n"
        "              n,(int32_t)ctx->gpr[28],(int32_t)ctx->gpr[25],\n"
        "              (uint32_t)ctx->gpr[26]); fflush(stderr);} }\n"
        "        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x160);\n"
        "        ctx->gpr[21] = vm_read64(ctx->gpr[1] + 0xF8);\n"
        "        ctx->gpr[22] = vm_read64(ctx->gpr[1] + 0x100);\n"
    )
    s5 = s5[:i] + region.replace(old, new, 1) + s5[j:]
    ch5 = True
    print("SS-DONE2: added")
else:
    print("SS-DONE2: already present")

if ch5:
    C5.write_text(s5, encoding="utf-8", newline="\n")
    print("OK wrote ppu_recomp_005.cpp")
else:
    print("005 unchanged")

# Grow path end in 003: trampoline to 003CC2B8
C3 = ROOT / "ppu_recomp_003.cpp"
s3 = C3.read_text(encoding="utf-8", errors="replace")
ch3 = False
if "[SS-GROW]" not in s3:
    old = (
        "        vm_write32(ctx->gpr[26] + 0xC, ctx->gpr[0]);\n"
        "        vm_write32(ctx->gpr[26] + 0x8, ctx->gpr[9]);\n"
        "        vm_write32(ctx->gpr[26] + 0x4, ctx->gpr[24]);\n"
        "        { g_trampoline_fn = (void(*)(void*))func_003CC2B8; return; }\n"
    )
    n = s3.count(old)
    if n != 1:
        raise SystemExit(f"SS-GROW needle count={n}")
    new = (
        "        vm_write32(ctx->gpr[26] + 0xC, ctx->gpr[0]);\n"
        "        vm_write32(ctx->gpr[26] + 0x8, ctx->gpr[9]);\n"
        "        vm_write32(ctx->gpr[26] + 0x4, ctx->gpr[24]);\n"
        f"        /* {MARKER}: grow done → resume */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<32)\n"
        "            fprintf(stderr,\"[SS-GROW] #%d N=%d newbase=0x%08X end=0x%08X\\n\",\n"
        "              n,(int32_t)ctx->gpr[25],(uint32_t)ctx->gpr[24],\n"
        "              (uint32_t)ctx->gpr[0]); fflush(stderr);} }\n"
        "        { g_trampoline_fn = (void(*)(void*))func_003CC2B8; return; }\n"
    )
    s3 = s3.replace(old, new, 1)
    ch3 = True
    print("SS-GROW: added")
else:
    print("SS-GROW: already present")

if ch3:
    C3.write_text(s3, encoding="utf-8", newline="\n")
    print("OK wrote ppu_recomp_003.cpp")
else:
    print("003 unchanged")

print("OK patch_shadersrc_loop")
