#!/usr/bin/env python3
"""CRC/combination lookup probes (2026-07-22).

After SHADERSRC materializes 889 CFX keys, does CGOWShader's precalc CRC
lookup (func_001655F0 → 001DEC38 hash → 00163088 map) hit anything?

Chain (verified):
  sprintf TEXTURE=…  →  func_001655F0  →  table=*(**(TOC-0x3B10)+0xCC)
  → 001643F8(table, shader, combo_str)
       → 001DEC38(combo_str)  // CRC32
       → 00163088(table, …)   // map lookup
       → store result at shader+0x10

Gated PS3_TRACE_CRCLK (fallback PS3_TRACE_COMBOPROP / PS3_TRACE_SHADERSRC).
OFF default. Read-only. Marker CRC-LK.
"""
from pathlib import Path
import sys

MARKER = "CRC-LK"

ROOT = (Path(sys.argv[1]) if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "recomp_macos_v2")
C0 = ROOT / "ppu_recomp_000.cpp"

s = C0.read_text(encoding="utf-8", errors="replace")
changed = False

PROBE_ON = (
    '{ static int on=-1; if(on<0){extern char* getenv(const char*);\n'
    '            const char* e=getenv("PS3_TRACE_CRCLK");\n'
    '            const char* e2=getenv("PS3_TRACE_COMBOPROP");\n'
    '            const char* e3=getenv("PS3_TRACE_SHADERSRC");\n'
    '            on=((e&&*e&&*e!=\'0\')||(e2&&*e2&&*e2!=\'0\')'
    '||(e3&&*e3&&*e3!=\'0\'))?1:0;}\n'
)


def guest_cstr_snippet():
    """C snippet: copy up to 48 printable chars from guest EA in variable `str_ea`."""
    return (
        "            char snip[52]; int si=0;\n"
        "            if(str_ea && str_ea < 0xFFF00000u){\n"
        "              for(; si<48; si++){\n"
        "                uint8_t c=vm_read8(str_ea+si);\n"
        "                if(!c) break;\n"
        "                snip[si]=(c>=32&&c<127)?(char)c:\'.\';\n"
        "              }\n"
        "            }\n"
        "            snip[si]=0;\n"
    )


if "[CRC-LK]" not in s:
    old = (
        "void func_001655F0(ppu_context* ctx) {\n"
        "        ctx->gpr[11] = vm_read32(ctx->gpr[2] + -0x3B10);\n"
        "        ctx->gpr[0] = ctx->lr;\n"
        "        vm_write64(ctx->gpr[1] + -0x70, ctx->gpr[1]); ctx->gpr[1] += -0x70;\n"
        "        vm_write64(ctx->gpr[1] + 0x80, ctx->gpr[0]);\n"
        "        ctx->gpr[9] = vm_read32(ctx->gpr[11] + 0x0);\n"
        "        ctx->gpr[3] = vm_read32(ctx->gpr[9] + 0xCC);\n"
        "        func_001643F8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
        "        /* nop */;\n"
        "        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x80);\n"
        "        ctx->gpr[1] = (int64_t)(int32_t)(ctx->gpr[1] + 0x70);\n"
        "        ctx->lr = ctx->gpr[0];\n"
        "        return;\n"
        "}\n"
    )
    new = (
        "void func_001655F0(ppu_context* ctx) {\n"
        f"        /* {MARKER}: combination CRC lookup */\n"
        "        uint32_t _crc_sh = (uint32_t)ctx->gpr[3];\n"
        "        uint32_t _crc_a4 = (uint32_t)ctx->gpr[4];\n"
        "        uint32_t _crc_str = (uint32_t)ctx->gpr[5];\n"
        "        ctx->gpr[11] = vm_read32(ctx->gpr[2] + -0x3B10);\n"
        "        ctx->gpr[0] = ctx->lr;\n"
        "        vm_write64(ctx->gpr[1] + -0x70, ctx->gpr[1]); ctx->gpr[1] += -0x70;\n"
        "        vm_write64(ctx->gpr[1] + 0x80, ctx->gpr[0]);\n"
        "        ctx->gpr[9] = vm_read32(ctx->gpr[11] + 0x0);\n"
        "        ctx->gpr[3] = vm_read32(ctx->gpr[9] + 0xCC);\n"
        "        uint32_t _crc_tbl = (uint32_t)ctx->gpr[3];\n"
        "        uint32_t _crc_root = (uint32_t)ctx->gpr[9];\n"
        "        uint32_t _crc_slot = (uint32_t)ctx->gpr[11];\n"
        "        func_001643F8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
        "        /* nop */;\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; static int hits=0, miss=0;\n"
        "            uint32_t res = _crc_sh ? vm_read32(_crc_sh + 0x10) : 0;\n"
        "            if(res) hits++; else miss++;\n"
        "            if(n++<48 || (n%200)==0){\n"
        "              uint32_t str_ea = _crc_str;\n"
        + guest_cstr_snippet() +
        "              fprintf(stderr,\n"
        "                \"[CRC-LK] #%d hit=%u res=0x%08X sh=0x%08X tbl=0x%08X root=0x%08X "
        "slot=0x%08X a4=0x%08X str=0x%08X '%s' hits=%d miss=%d\\n\",\n"
        "                n, res?1:0, res, _crc_sh, _crc_tbl, _crc_root, _crc_tbl,\n"
        "                _crc_a4, _crc_str, snip, hits, miss);\n"
        "              fflush(stderr);\n"
        "            } } }\n"
        "        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x80);\n"
        "        ctx->gpr[1] = (int64_t)(int32_t)(ctx->gpr[1] + 0x70);\n"
        "        ctx->lr = ctx->gpr[0];\n"
        "        return;\n"
        "}\n"
    )
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"CRC-LK body needle count={n}")
    s = s.replace(old, new, 1)
    changed = True
    print("CRC-LK: added on 001655F0")
else:
    print("CRC-LK: already present")

# Hash probe inside 001643F8 after 001DEC38
if "[CRC-HASH]" not in s:
    old = (
        "        func_001DEC38(ctx); DRAIN_TRAMPOLINE(ctx);\n"
        "        /* nop */;\n"
        "        ctx->gpr[5] = ppc_rldicl(ctx->gpr[3], 0, 32);\n"
        "        ctx->gpr[4] = ppc_rldicl(ctx->gpr[29], 0, 32);\n"
        "        ctx->gpr[3] = ppc_rldicl(ctx->gpr[27], 0, 32);\n"
        "        ctx->gpr[6] = ctx->gpr[28] | ctx->gpr[28];\n"
        "        func_00163088(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    new = (
        "        func_001DEC38(ctx); DRAIN_TRAMPOLINE(ctx);\n"
        "        /* nop */;\n"
        f"        /* {MARKER}: CRC32 of combination string */\n"
        f"        {PROBE_ON}"
        "          if(on){ static int n=0; if(n++<48)\n"
        "            fprintf(stderr,\"[CRC-HASH] #%d crc=0x%08X str=0x%08X tbl=0x%08X\\n\",\n"
        "              n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[28],\n"
        "              (uint32_t)ctx->gpr[27]); fflush(stderr);} }\n"
        "        ctx->gpr[5] = ppc_rldicl(ctx->gpr[3], 0, 32);\n"
        "        ctx->gpr[4] = ppc_rldicl(ctx->gpr[29], 0, 32);\n"
        "        ctx->gpr[3] = ppc_rldicl(ctx->gpr[27], 0, 32);\n"
        "        ctx->gpr[6] = ctx->gpr[28] | ctx->gpr[28];\n"
        "        func_00163088(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    )
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"CRC-HASH needle count={n}")
    s = s.replace(old, new, 1)
    changed = True
    print("CRC-HASH: added")
else:
    print("CRC-HASH: already present")

# One-shot dump of CRC table root after SHADERSRC era: hook first CRC-LK only
# already dumps tbl/root. Also dump table head fields if tbl non-null:
# We enhance first log via separate helper on 001655F0 when n==1 — already have tbl.

if changed:
    C0.write_text(s, encoding="utf-8", newline="\n")
    print("OK wrote ppu_recomp_000.cpp")
else:
    print("000 unchanged")
print("OK patch_crc_lookup_probe")
