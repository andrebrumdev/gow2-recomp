#!/usr/bin/env python3
"""A1 chain probes (2026-07-22): entry counts + gate values above 0032E200.

WHY
---
Static RE (notes/2026-07-21-registry-caller-chain-A1.md) proved that the only
direct path to func_0032E200 is:

  00468C3C -> 00330D54 -> 0032DF98  [if *r5 != 0]  -> 0032E200 -> walk

and that 00468C3C always stores literal 0 at sp+0x7C, which becomes *r5 in
0032DF98. That closes the gate *structurally*. This patch only *measures*
in-boot whether:
  - 00468C3C is visited after WAD
  - it reaches 00330D54 / 0032DF98 (or early-exits to 00468DF8)
  - *r5 is always 0 (confirming the static claim in-boot)
  - the E200 branch is never taken

Gated by PS3_TRACE_A1CHAIN (fallback PS3_TRACE_TYMAP). OFF by default.
Read-only (stderr logs only). Idempotent (marker A1-CHAIN). Never forges
gates / CRC / SHADERSRC.
"""
from pathlib import Path
import sys

MARKER = "A1-CHAIN"

ROOT = (Path(sys.argv[1]) if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "recomp_macos_v2")
C1 = ROOT / "ppu_recomp_001.cpp"
C2 = ROOT / "ppu_recomp_002.cpp"

PROBE_ON = (
    '{ static int on=-1; if(on<0){extern char* getenv(const char*);\n'
    '            const char* e=getenv("PS3_TRACE_A1CHAIN"); '
    'const char* e2=getenv("PS3_TRACE_TYMAP");\n'
    '            on=((e&&*e&&*e!=\'0\')||(e2&&*e2&&*e2!=\'0\'))?1:0;}\n'
)

s = C1.read_text(encoding="utf-8", errors="replace")
changed = False


def add_once(label, old, new):
    global s, changed
    if f"[{label}]" in s:
        print(f"{label}: already present")
        return
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"{label}: needle count={n} (expected 1)")
    s = s.replace(old, new, 1)
    changed = True
    print(f"{label}: probe added")


# --- 1) Entry of func_00468C3C ---
add_once(
    "A1-468C3C",
    "void func_00468C3C(ppu_context* ctx) {\n"
    "        vm_write64(ctx->gpr[1] + -0xD0, ctx->gpr[1]); ctx->gpr[1] += -0xD0;\n",
    "void func_00468C3C(ppu_context* ctx) {\n"
    f"        /* {MARKER}: entry */\n"
    f"        {PROBE_ON}"
    "          if(on){ static int n=0; if(n++<64)\n"
    "            fprintf(stderr,\"[A1-468C3C] #%d r3=0x%08X r4=0x%08X r5=0x%08X r6=0x%08X\\n\",\n"
    "              n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[4],\n"
    "              (uint32_t)ctx->gpr[5],(uint32_t)ctx->gpr[6]); fflush(stderr);} }\n"
    "        vm_write64(ctx->gpr[1] + -0xD0, ctx->gpr[1]); ctx->gpr[1] += -0xD0;\n",
)

# --- 2) Early exit EX1 to 00468DF8 (field0==0) ---
if "[A1-468-EX1]" not in s:
    old_ex1 = (
        "        if (((ctx->cr >> 0) & 2)) { g_trampoline_fn = (void(*)(void*))func_00468DF8; return; }\n"
        "        ctx->gpr[9] = ppc_rldicl(ctx->gpr[9], 0, 32);\n"
    )
    new_ex1 = (
        f"        /* {MARKER} */\n"
        f"        {PROBE_ON}"
        "          if(on && ((ctx->cr >> 0) & 2)){ static int n=0; if(n++<32)\n"
        "            fprintf(stderr,\"[A1-468-EX1] #%d early DF8 (field0==0) r5=0x%08X\\n\",\n"
        "              n,(uint32_t)ctx->gpr[31]); fflush(stderr);} }\n"
        "        if (((ctx->cr >> 0) & 2)) { g_trampoline_fn = (void(*)(void*))func_00468DF8; return; }\n"
        "        ctx->gpr[9] = ppc_rldicl(ctx->gpr[9], 0, 32);\n"
    )
    n = s.count(old_ex1)
    if n != 1:
        raise SystemExit(f"A1-468-EX1 needle count={n}")
    s = s.replace(old_ex1, new_ex1, 1)
    changed = True
    print("A1-468-EX1: probe added")
else:
    print("A1-468-EX1: already present")

# --- 3) Early exit EX2 to 00468DF8 (field8==0) ---
if "[A1-468-EX2]" not in s:
    old_ex2 = (
        "        if (((ctx->cr >> 0) & 2)) { g_trampoline_fn = (void(*)(void*))func_00468DF8; return; }\n"
        "        ctx->gpr[3] = (int64_t)(int32_t)(0x14);\n"
    )
    new_ex2 = (
        f"        /* {MARKER} */\n"
        f"        {PROBE_ON}"
        "          if(on && ((ctx->cr >> 0) & 2)){ static int n=0; if(n++<32)\n"
        "            fprintf(stderr,\"[A1-468-EX2] #%d early DF8 (field8==0) r5=0x%08X\\n\",\n"
        "              n,(uint32_t)ctx->gpr[31]); fflush(stderr);} }\n"
        "        if (((ctx->cr >> 0) & 2)) { g_trampoline_fn = (void(*)(void*))func_00468DF8; return; }\n"
        "        ctx->gpr[3] = (int64_t)(int32_t)(0x14);\n"
    )
    n = s.count(old_ex2)
    if n != 1:
        raise SystemExit(f"A1-468-EX2 needle count={n}")
    s = s.replace(old_ex2, new_ex2, 1)
    changed = True
    print("A1-468-EX2: probe added")
else:
    print("A1-468-EX2: already present")

# --- 4) Entry of func_00330D54 (before PRE tags that contain the same prefix) ---
add_once(
    "A1-30D54",
    "void func_00330D54(ppu_context* ctx) {\n"
    "        vm_write64(ctx->gpr[1] + -0xE0, ctx->gpr[1]); ctx->gpr[1] += -0xE0;\n",
    "void func_00330D54(ppu_context* ctx) {\n"
    f"        /* {MARKER}: entry */\n"
    f"        {PROBE_ON}"
    "          if(on){ static int n=0; if(n++<64){\n"
    "            uint32_t r6=(uint32_t)ctx->gpr[6]; uint32_t v=r6?vm_read32(r6):0;\n"
    "            fprintf(stderr,\"[A1-30D54] #%d r3=0x%08X r5=0x%08X r6=0x%08X *r6=0x%08X r8=0x%08X\\n\",\n"
    "              n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[5],r6,v,(uint32_t)ctx->gpr[8]);\n"
    "            fflush(stderr);} } }\n"
    "        vm_write64(ctx->gpr[1] + -0xE0, ctx->gpr[1]); ctx->gpr[1] += -0xE0;\n",
)

# --- 5) Pre-call 00330D54 inside 00468C3C (inline path) ---
if "[A1-CALL30D54]" not in s:
    old_call = (
        "        vm_write32(ctx->gpr[1] + 0x7C, ctx->gpr[30]);\n"
        "        vm_write32(ctx->gpr[1] + 0x70, ctx->gpr[27]);\n"
        "        func_00330D54(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    new_call = (
        "        vm_write32(ctx->gpr[1] + 0x7C, ctx->gpr[30]);\n"
        "        vm_write32(ctx->gpr[1] + 0x70, ctx->gpr[27]);\n"
        f"        /* {MARKER}: pre-call 00330D54 */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<64)\n"
        "            fprintf(stderr,\"[A1-CALL30D54] #%d sp7c=*r30=0x%08X r6arg=0x%08X r8=0x%08X\\n\",\n"
        "              n,(uint32_t)ctx->gpr[30],(uint32_t)(ctx->gpr[1]+0x7C),\n"
        "              (uint32_t)ctx->gpr[26]); fflush(stderr);} }\n"
        "        func_00330D54(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    n = s.count(old_call)
    if n != 1:
        raise SystemExit(f"A1-CALL30D54 needle count={n}")
    s = s.replace(old_call, new_call, 1)
    changed = True
    print("A1-CALL30D54: probe added")
else:
    print("A1-CALL30D54: already present")

# --- 6) Gate inside func_0032DF98 ---
if "[A1-32DF98]" not in s:
    old_br = (
        "        vm_write32(ctx->gpr[1] + 0x1C8, ctx->gpr[8]);\n"
        "        if ((!((ctx->cr >> 0) & 2))) { g_trampoline_fn = (void(*)(void*))func_0032E200; return; }\n"
        "        { int64_t a = (int32_t)ctx->gpr[8]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 4)) | (cr_val << 4); }\n"
        "        if ((!((ctx->cr >> 4) & 2))) { g_trampoline_fn = (void(*)(void*))func_0032E718; return; }\n"
    )
    new_br = (
        "        vm_write32(ctx->gpr[1] + 0x1C8, ctx->gpr[8]);\n"
        f"        /* {MARKER}: gate *r5 / r8 */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<96){\n"
        "            uint32_t r5=(uint32_t)ctx->gpr[5]; uint32_t star=r5?vm_read32(r5):0;\n"
        "            const char* br = (!((ctx->cr >> 0) & 2)) ? \"E200\"\n"
        "              : (((int32_t)ctx->gpr[8]) != 0) ? \"E718\" : \"DEFAULT\";\n"
        "            fprintf(stderr,\"[A1-32DF98] #%d r5=0x%08X *r5=0x%08X r8=0x%08X br=%s\\n\",\n"
        "              n,r5,star,(uint32_t)ctx->gpr[8],br); fflush(stderr);} } }\n"
        "        if ((!((ctx->cr >> 0) & 2))) { g_trampoline_fn = (void(*)(void*))func_0032E200; return; }\n"
        "        { int64_t a = (int32_t)ctx->gpr[8]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 4)) | (cr_val << 4); }\n"
        "        if ((!((ctx->cr >> 4) & 2))) { g_trampoline_fn = (void(*)(void*))func_0032E718; return; }\n"
    )
    n = s.count(old_br)
    if n != 1:
        raise SystemExit(f"A1-32DF98 needle count={n}")
    s = s.replace(old_br, new_br, 1)
    changed = True
    print("A1-32DF98: probe added")
else:
    print("A1-32DF98: already present")

# --- 7) 002 paths (468CEC / 468D04) pre-call ---
s2 = C2.read_text(encoding="utf-8", errors="replace")
changed2 = False
if "[A1-CALL30D54B]" not in s2:
    old2 = (
        "        vm_write32(ctx->gpr[1] + 0x7C, ctx->gpr[30]);\n"
        "        vm_write32(ctx->gpr[1] + 0x70, ctx->gpr[27]);\n"
        "        func_00330D54(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    new2 = (
        "        vm_write32(ctx->gpr[1] + 0x7C, ctx->gpr[30]);\n"
        "        vm_write32(ctx->gpr[1] + 0x70, ctx->gpr[27]);\n"
        f"        /* {MARKER}: pre-call 00330D54 via 468CEC/D04 */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<64)\n"
        "            fprintf(stderr,\"[A1-CALL30D54B] #%d sp7c_r30=0x%08X\\n\",\n"
        "              n,(uint32_t)ctx->gpr[30]); fflush(stderr);} }\n"
        "        func_00330D54(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    n = s2.count(old2)
    if n != 2:
        raise SystemExit(f"A1-CALL30D54B needle count={n} (expected 2 in 002)")
    s2 = s2.replace(old2, new2)
    changed2 = True
    print(f"A1-CALL30D54B: probe added x{n}")
else:
    print("A1-CALL30D54B: already present")

if changed:
    C1.write_text(s, encoding="utf-8", newline="\n")
    print("OK wrote ppu_recomp_001.cpp")
else:
    print("001 unchanged")

if changed2:
    C2.write_text(s2, encoding="utf-8", newline="\n")
    print("OK wrote ppu_recomp_002.cpp")
else:
    print("002 unchanged")

print("OK patch_a1_chain_probe")
