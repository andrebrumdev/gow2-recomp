#!/usr/bin/env python3
"""Instrument WAD type-system state machine + fix OPD in func_002B9C80.

Path (discovered):
  type_sys = *TOC-0x122C
  state = type_sys+0x1CC  (1=open, 2=read header, 3=read body)
  func_002BA76C state machine
  state 3 → func_002BAB88 → func_002B9C80(header, buf)
  2B9C80: type = *(u16*)header; OPD = table[type]+8; call OPD
  This is how GroupStart/type factories fire for streamed WAD members.

Also switch OPD dispatch to ps3_call_opd (same class of fix as Task4).
"""
from __future__ import annotations
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
C1 = ROOT / "ppu_recomp_001.cpp"
s = C1.read_text(encoding="utf-8", errors="replace")

# --- declare ps3_call_opd if missing in 001 ---
if "void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);" not in s:
    old = 'extern "C" void ps3_indirect_call(ppu_context* ctx);'
    if old not in s:
        raise SystemExit("ps3_indirect_call decl missing in 001")
    s = s.replace(
        old,
        old + '\nextern "C" void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);',
        1,
    )
    print("001: declared ps3_call_opd")

# --- probe + OPD fix in 2B9C80 ---
if "WADLD-CALL" not in s:
    old = """void func_002B9C80(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0x90, ctx->gpr[1]); ctx->gpr[1] += -0x90;
        ctx->gpr[0] = ctx->lr;
        vm_write64(ctx->gpr[1] + 0x80, ctx->gpr[30]);
        vm_write64(ctx->gpr[1] + 0x88, ctx->gpr[31]);
        vm_write64(ctx->gpr[1] + 0xA0, ctx->gpr[0]);
        vm_write64(ctx->gpr[1] + 0x78, ctx->gpr[29]);
        ctx->gpr[31] = ctx->gpr[3] | ctx->gpr[3];
        ctx->gpr[3] = vm_read16(ctx->gpr[3] + 0x0);
        ctx->gpr[30] = ctx->gpr[4] | ctx->gpr[4];
        func_002B9C68(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[0] = ctx->gpr[3] | ctx->gpr[3];
        ctx->gpr[9] = ppc_rldicl(ctx->gpr[3], 0, 32);
        { int64_t a = (int32_t)ctx->gpr[0]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        ctx->gpr[4] = ppc_rldicl(ctx->gpr[30], 0, 32);
        ctx->gpr[3] = ctx->gpr[31] | ctx->gpr[31];
        if (((ctx->cr >> 0) & 2)) goto loc_002B9CD8;
        ctx->gpr[0] = vm_read32(ctx->gpr[9] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[9] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
loc_002B9CD8:"""
    new = """void func_002B9C80(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0x90, ctx->gpr[1]); ctx->gpr[1] += -0x90;
        ctx->gpr[0] = ctx->lr;
        vm_write64(ctx->gpr[1] + 0x80, ctx->gpr[30]);
        vm_write64(ctx->gpr[1] + 0x88, ctx->gpr[31]);
        vm_write64(ctx->gpr[1] + 0xA0, ctx->gpr[0]);
        vm_write64(ctx->gpr[1] + 0x78, ctx->gpr[29]);
        ctx->gpr[31] = ctx->gpr[3] | ctx->gpr[3];
        ctx->gpr[3] = vm_read16(ctx->gpr[3] + 0x0);
        ctx->gpr[30] = ctx->gpr[4] | ctx->gpr[4];
        /* Task5: WAD member type-loader dispatch. type=u16 header; table[type] OPD. */
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<64){
            uint32_t ty=(uint32_t)ctx->gpr[3], hdr=(uint32_t)ctx->gpr[31], buf=(uint32_t)ctx->gpr[30];
            fprintf(stderr,"[WADLD-CALL] #%d type=%u hdr=0x%08X buf=0x%08X\\n", n, ty, hdr, buf); fflush(stderr);} } }
        func_002B9C68(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[0] = ctx->gpr[3] | ctx->gpr[3];
        ctx->gpr[9] = ppc_rldicl(ctx->gpr[3], 0, 32);
        { int64_t a = (int32_t)ctx->gpr[0]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        ctx->gpr[4] = ppc_rldicl(ctx->gpr[30], 0, 32);
        ctx->gpr[3] = ctx->gpr[31] | ctx->gpr[31];
        if (((ctx->cr >> 0) & 2)) goto loc_002B9CD8;
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<64)
            fprintf(stderr,"[WADLD-OPD] #%d opd=0x%08X code_peek=0x%08X\\n",
              n,(uint32_t)ctx->gpr[9], vm_read32(ctx->gpr[9]+0x0)); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[9]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
loc_002B9CD8:"""
    if old not in s:
        raise SystemExit("2B9C80 needle missing")
    s = s.replace(old, new, 1)
    print("patched 2B9C80")
else:
    print("2B9C80 already patched")

# --- probe state machine 2BA76C ---
if "WADLD-SM" not in s:
    old = """void func_002BA76C(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0xB0, ctx->gpr[1]); ctx->gpr[1] += -0xB0;
        ctx->gpr[0] = ctx->lr;
        vm_write64(ctx->gpr[1] + 0xA8, ctx->gpr[31]);
        ctx->gpr[31] = vm_read32(ctx->gpr[2] + -0x122C);"""
    new = """void func_002BA76C(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0xB0, ctx->gpr[1]); ctx->gpr[1] += -0xB0;
        ctx->gpr[0] = ctx->lr;
        vm_write64(ctx->gpr[1] + 0xA8, ctx->gpr[31]);
        ctx->gpr[31] = vm_read32(ctx->gpr[2] + -0x122C);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<80){
            uint32_t ts=(uint32_t)ctx->gpr[31];
            fprintf(stderr,"[WADLD-SM] #%d ts=0x%08X state=%u rem=0x%X flag1B0=%u\\n",
              n, ts, vm_read32(ts+0x1CC), vm_read32(ts+0x1AC), vm_read32(ts+0x1B0)); fflush(stderr);} } }"""
    if old not in s:
        raise SystemExit("2BA76C needle missing")
    s = s.replace(old, new, 1)
    print("patched 2BA76C probe")
else:
    print("2BA76C already")

# --- probe 2BAB88 body-done path (before 2B9C80) ---
if "WADLD-BODY" not in s:
    old = """        ctx->gpr[29] = (int64_t)(int32_t)(ctx->gpr[31] + 0x7C);
        ctx->gpr[4] = vm_read32(ctx->gpr[31] + 0x1C4);
        ctx->gpr[29] = ppc_rldicl(ctx->gpr[29], 0, 32);
        ctx->gpr[3] = ctx->gpr[29] | ctx->gpr[29];
        func_002B9BFC(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[3] = ctx->gpr[29] | ctx->gpr[29];
        ctx->gpr[4] = vm_read32(ctx->gpr[31] + 0x1C4);
        func_002B9C80(ctx); DRAIN_TRAMPOLINE(ctx);"""
    new = """        ctx->gpr[29] = (int64_t)(int32_t)(ctx->gpr[31] + 0x7C);
        ctx->gpr[4] = vm_read32(ctx->gpr[31] + 0x1C4);
        ctx->gpr[29] = ppc_rldicl(ctx->gpr[29], 0, 32);
        ctx->gpr[3] = ctx->gpr[29] | ctx->gpr[29];
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<40){
            uint32_t hdr=(uint32_t)ctx->gpr[3], buf=(uint32_t)ctx->gpr[4];
            uint16_t ty=vm_read16(hdr+0x0);
            fprintf(stderr,"[WADLD-BODY] #%d hdr=0x%08X buf=0x%08X type16=%u name4=0x%08X\\n",
              n, hdr, buf, ty, vm_read32(hdr+0x8)); fflush(stderr);} } }
        func_002B9BFC(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[3] = ctx->gpr[29] | ctx->gpr[29];
        ctx->gpr[4] = vm_read32(ctx->gpr[31] + 0x1C4);
        func_002B9C80(ctx); DRAIN_TRAMPOLINE(ctx);"""
    if old not in s:
        raise SystemExit("2BAB88 body needle missing")
    s = s.replace(old, new, 1)
    print("patched WADLD-BODY probe")
else:
    print("BODY already")

C1.write_text(s, encoding="utf-8", newline="\n")
print("OK patch_wad_state_machine")
