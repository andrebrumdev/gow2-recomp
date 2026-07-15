#!/usr/bin/env python3
"""Task 5 / ICGLdr unlock: instrument type-map lookup + fix OPD dispatch.

Hypothesis: ICGLdrShader (0xF85F9B1E) is registered into the map at TOC+0xD8C/D90
via func_0018F160, but the lookup path (func_00171244 → func_0018E814) either
never runs, uses a different map (TOC-0x3A3C), or fails the node+0x10 OPD call
(ps3_indirect_call treats OPD as code).

This patch (idempotent):
  1. Declare ps3_call_opd in ppu_recomp_000.cpp
  2. [TYMAP] probe at entry/exit of func_0018E814 (map, type, hit/miss, maps)
  3. Replace node+0x10 OPD path in 18E814 with ps3_call_opd
  4. Replace pre-lookup OPD in 171244 with ps3_call_opd
  5. [TYMAP-REG] probe on registration (func_00321034) comparing map pointers
"""
from __future__ import annotations
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
C0 = ROOT / "ppu_recomp_000.cpp"
C1 = ROOT / "ppu_recomp_001.cpp"
MARKER = "Task5 TYMAP"

def must(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    return path.read_text(encoding="utf-8", errors="replace")

def write(path: Path, s: str) -> None:
    path.write_text(s, encoding="utf-8", newline="\n")

# --- 1) declare ps3_call_opd in chunk 000 ---
s0 = must(C0)
if "void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);" not in s0:
    old = 'extern "C" void ps3_indirect_call(ppu_context* ctx);'
    if old not in s0:
        raise SystemExit("ps3_indirect_call decl missing in 000")
    s0 = s0.replace(
        old,
        old + '\nextern "C" void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);',
        1,
    )
    print("000: declared ps3_call_opd")
else:
    print("000: ps3_call_opd already declared")

# --- 2) probe + OPD fix in func_0018E814 ---
if MARKER not in s0 or "TYMAP-LK" not in s0:
    # entry probe right after function open
    entry_old = """void func_0018E814(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0x70, ctx->gpr[1]); ctx->gpr[1] += -0x70;
        ctx->gpr[0] = ctx->lr;
        vm_write64(ctx->gpr[1] + 0x80, ctx->gpr[0]);
        ctx->gpr[7] = vm_read32(ctx->gpr[3] + 0x0);"""
    entry_new = """void func_0018E814(ppu_context* ctx) {
        /* Task5 TYMAP: type-map lookup (map=r3, type=r4, out=r5). Compare map
         * against TOC+0xD8C (ICGLdr register map) and TOC-0x3A3C (171244 map). */
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<64){
            uint32_t map=(uint32_t)ctx->gpr[3], ty=(uint32_t)ctx->gpr[4];
            uint32_t d8c=vm_read32(ctx->gpr[2]+0xD8C), d90=vm_read32(ctx->gpr[2]+0xD90);
            uint32_t m3a=vm_read32(ctx->gpr[2]+(uint32_t)(-0x3A3C));
            fprintf(stderr,"[TYMAP-LK] #%d map=0x%08X type=0x%08X d8c=0x%08X d90=0x%08X m3a3c=0x%08X same_d8c=%d same_d90=%d same_m3a=%d\\n",
              n,map,ty,d8c,d90,m3a,map==d8c,map==d90,map==m3a); fflush(stderr);} } }
        vm_write64(ctx->gpr[1] + -0x70, ctx->gpr[1]); ctx->gpr[1] += -0x70;
        ctx->gpr[0] = ctx->lr;
        vm_write64(ctx->gpr[1] + 0x80, ctx->gpr[0]);
        ctx->gpr[7] = vm_read32(ctx->gpr[3] + 0x0);"""
    if entry_old not in s0:
        raise SystemExit("18E814 entry needle missing")
    s0 = s0.replace(entry_old, entry_new, 1)
    print("000: TYMAP-LK entry probe")

    # OPD call site inside 18E814
    opd_old = """        ctx->gpr[9] = ppc_rldicl(ctx->gpr[11], 0, 32);
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[5], 0, 32);
        ctx->gpr[4] = (int64_t)(int32_t)(0);
        ctx->gpr[11] = vm_read32(ctx->gpr[9] + 0x10);
        ctx->gpr[0] = vm_read32(ctx->gpr[11] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[11] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
loc_0018E8BC:"""
    opd_new = """        ctx->gpr[9] = ppc_rldicl(ctx->gpr[11], 0, 32);
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[5], 0, 32);
        ctx->gpr[4] = (int64_t)(int32_t)(0);
        ctx->gpr[11] = vm_read32(ctx->gpr[9] + 0x10);
        /* Task5 TYMAP: node+0x10 is an OPD (or direct code EA); use ps3_call_opd. */
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<32)
            fprintf(stderr,"[TYMAP-HIT] #%d node=0x%08X opd=0x%08X type_key_via_r30_ish\\n",
              n,(uint32_t)ctx->gpr[9],(uint32_t)ctx->gpr[11]); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[11]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
loc_0018E8BC:"""
    # Only replace first occurrence inside 18E814 region
    i_fn = s0.find("void func_0018E814")
    i_next = s0.find("void func_0018E8D0", i_fn)
    if i_fn < 0 or i_next < 0:
        raise SystemExit("18E814 region bounds missing")
    region = s0[i_fn:i_next]
    if "ps3_call_opd(ctx, (uint32_t)ctx->gpr[11])" in region and "TYMAP-HIT" in region:
        print("000: 18E814 OPD already patched")
    else:
        if opd_old not in region:
            # try without loc label exact
            raise SystemExit("18E814 OPD needle missing in region")
        region2 = region.replace(opd_old, opd_new, 1)
        s0 = s0[:i_fn] + region2 + s0[i_next:]
        print("000: 18E814 OPD -> ps3_call_opd + TYMAP-HIT")

    # miss/hit result at epilogue of 18E814 (loc_0018E8BC)
    epi_old = """loc_0018E8BC:
        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x80);
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[3], 0, 32);
        ctx->gpr[1] = (int64_t)(int32_t)(ctx->gpr[1] + 0x70);
        ctx->lr = ctx->gpr[0];
        return;
}

void func_0018E8D0(ppu_context* ctx) {"""
    epi_new = """loc_0018E8BC:
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<64)
            fprintf(stderr,"[TYMAP-RET] #%d r3=0x%08X\\n", n, (uint32_t)ctx->gpr[3]); fflush(stderr);} }
        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x80);
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[3], 0, 32);
        ctx->gpr[1] = (int64_t)(int32_t)(ctx->gpr[1] + 0x70);
        ctx->lr = ctx->gpr[0];
        return;
}

void func_0018E8D0(ppu_context* ctx) {"""
    if "TYMAP-RET" not in s0:
        if epi_old not in s0:
            raise SystemExit("18E814 epilogue needle missing")
        s0 = s0.replace(epi_old, epi_new, 1)
        print("000: TYMAP-RET probe")
    else:
        print("000: TYMAP-RET already present")
else:
    print("000: TYMAP markers already present (partial?)")

# --- 3) OPD fix in func_00171244 pre-lookup vtable call ---
i_fn = s0.find("void func_00171244")
i_next = s0.find("void func_00171350", i_fn)
if i_fn < 0 or i_next < 0:
    raise SystemExit("171244 region missing")
region = s0[i_fn:i_next]
opd171_old = """        ctx->gpr[0] = vm_read32(ctx->gpr[9] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[9] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[4] = ctx->gpr[29] | ctx->gpr[29];
        ctx->gpr[0] = (int64_t)(int32_t)(0);
        ctx->gpr[28] = vm_read32(ctx->gpr[2] + -0x3A3C);"""
opd171_new = """        /* Task5 TYMAP: vtable slot is OPD; use ps3_call_opd before map lookup. */
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<32)
            fprintf(stderr,"[TYMAP-VT] #%d opd_slot=0x%08X type_tag=0x%08X\\n",
              n,(uint32_t)ctx->gpr[9],(uint32_t)ctx->gpr[29]); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[9]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[4] = ctx->gpr[29] | ctx->gpr[29];
        ctx->gpr[0] = (int64_t)(int32_t)(0);
        ctx->gpr[28] = vm_read32(ctx->gpr[2] + -0x3A3C);"""
if "TYMAP-VT" in region:
    print("000: 171244 OPD already patched")
else:
    if opd171_old not in region:
        raise SystemExit("171244 OPD needle missing")
    region2 = region.replace(opd171_old, opd171_new, 1)
    s0 = s0[:i_fn] + region2 + s0[i_next:]
    print("000: 171244 OPD -> ps3_call_opd + TYMAP-VT")

write(C0, s0)

# --- 4) registration probe in chunk 001 ---
s1 = must(C1)
if "TYMAP-REG" in s1:
    print("001: TYMAP-REG already present")
else:
    reg_old = """void func_00321034(ppu_context* ctx) {
        /* ROTA A (PS3_TRACE_SHREG): registração do ICGLdrShader (tipo 0xF85F9B1E).
         * Se FIRAR => o loader de shader É registrado (dispatch deveria ocorrer).
         * Se NÃO firar => a registração/init do subsistema de shader nunca roda = O BUG. */
        { static int sr=-1; if(sr<0){extern char* getenv(const char*); sr=getenv("PS3_TRACE_SHREG")?1:0;}
          if(sr){ static int n=0; if(n<8){ n++; fprintf(stderr,"[SHREG] #%d REGISTRA ICGLdrShader (tipo 0xF85F9B1E) FIROU\\n",n); fflush(stderr);} } }
        ctx->gpr[5] = (int64_t)(int32_t)(0);
        ctx->gpr[7] = (int64_t)(int32_t)(0);
        ctx->gpr[5] = ctx->gpr[5] | ((uint64_t)0xF85F << 16);
        if ((!((ctx->cr >> 24) & 2))) { g_trampoline_fn = (void(*)(void*))func_00321024; return; }
        ctx->gpr[5] = ctx->gpr[5] | 0x9B1E;
        ctx->gpr[6] = vm_read32(ctx->gpr[2] + 0xD94);
        ctx->gpr[3] = vm_read32(ctx->gpr[2] + 0xD8C);
        ctx->gpr[4] = vm_read32(ctx->gpr[2] + 0xD90);
        func_0018F160(ctx); DRAIN_TRAMPOLINE(ctx);"""
    reg_new = """void func_00321034(ppu_context* ctx) {
        /* ROTA A (PS3_TRACE_SHREG): registração do ICGLdrShader (tipo 0xF85F9B1E).
         * Se FIRAR => o loader de shader É registrado (dispatch deveria ocorrer).
         * Se NÃO firar => a registração/init do subsistema de shader nunca roda = O BUG. */
        { static int sr=-1; if(sr<0){extern char* getenv(const char*); sr=getenv("PS3_TRACE_SHREG")?1:0;}
          if(sr){ static int n=0; if(n<8){ n++; fprintf(stderr,"[SHREG] #%d REGISTRA ICGLdrShader (tipo 0xF85F9B1E) FIROU\\n",n); fflush(stderr);} } }
        ctx->gpr[5] = (int64_t)(int32_t)(0);
        ctx->gpr[7] = (int64_t)(int32_t)(0);
        ctx->gpr[5] = ctx->gpr[5] | ((uint64_t)0xF85F << 16);
        if ((!((ctx->cr >> 24) & 2))) { g_trampoline_fn = (void(*)(void*))func_00321024; return; }
        ctx->gpr[5] = ctx->gpr[5] | 0x9B1E;
        ctx->gpr[6] = vm_read32(ctx->gpr[2] + 0xD94);
        ctx->gpr[3] = vm_read32(ctx->gpr[2] + 0xD8C);
        ctx->gpr[4] = vm_read32(ctx->gpr[2] + 0xD90);
        /* Task5 TYMAP: dump register-side map pointers vs lookup TOC-0x3A3C. */
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=(getenv("PS3_TRACE_TYMAP")||getenv("PS3_TRACE_SHREG"))?1:0;}
          if(on){ static int n=0; if(n++<8){
            uint32_t d8c=(uint32_t)ctx->gpr[3], d90=(uint32_t)ctx->gpr[4], d94=(uint32_t)ctx->gpr[6];
            uint32_t m3a=vm_read32(ctx->gpr[2]+(uint32_t)(-0x3A3C));
            fprintf(stderr,"[TYMAP-REG] #%d type=0xF85F9B1E d8c=0x%08X d90=0x%08X d94=0x%08X m3a3c=0x%08X d8c_eq_m3a=%d d90_eq_m3a=%d\\n",
              n,d8c,d90,d94,m3a,d8c==m3a,d90==m3a); fflush(stderr);} } }
        func_0018F160(ctx); DRAIN_TRAMPOLINE(ctx);"""
    if reg_old not in s1:
        raise SystemExit("321034 registration needle missing")
    s1 = s1.replace(reg_old, reg_new, 1)
    write(C1, s1)
    print("001: TYMAP-REG probe")

print("OK: patch_tymap_18e814 applied")
