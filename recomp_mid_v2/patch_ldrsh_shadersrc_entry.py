#!/usr/bin/env python3
"""Task 3 (Boot N1 discriminador, 2026-07-21): instala os dois marcadores que o
script de contagem do plano espera literalmente ([LDRSH], [SHADERSRC] N=) e que
nenhum patch anterior instala com esse nome exacto.

  - [LDRSH] entry probe em func_0032109C (corpo do ICGLdrShader, tag
    0x283F6879 -- ver anchors confirmadas em ppu_recomp_001.cpp:136228).
    Sinaliza "o corpo da instancia ICGLdrShader correu de facto". O
    comentario do runtime em ppu_loader.cpp:2077 ("LDRSH=0") refere-se a
    esta funcao. Gated por PS3_TRACE_LDRSH (fallback PS3_TRACE_TYMAP, mesma
    convencao dos outros probes deste plano).

  - [SHADERSRC] N=<n> em func_003CC208 (defs SHADERSRC -- anchor confirmada
    em ppu_recomp_001.cpp:291118), logo apos o campo de contagem de 4 bytes
    ser lido do stream via func_001856A8 (r3=stream, r4=&local, r5=4) para
    ctx->gpr[1]+0x70 -> ctx->gpr[25]. E o mesmo valor que o probe (retirado)
    do lado Windows reportava -- ver smoke_asset_pipeline.sh: "N=-1" =
    nenhum shader encontrado, "N>=0" = contagem real. Gated por
    PS3_TRACE_SHADERSRC (fallback PS3_TRACE_TYMAP).

Nota de confianca (RE estatica, nao documentacao oficial): gpr[25] e lido
como u32 logo no entry do stream e depois usado como limite de um loop
(comparado contra um contador gpr[28] que incrementa de 0 em 1) -- e
consistente com "N = numero de records declarados no header do stream",
mas fica sujeito a confirmacao pelos valores reais observados no boot N1
(se N vier sempre um inteiro pequeno ou -1, confirma; se vier lixo, ver
nota no relatorio).

Ambos sao diagnosticos puros em stderr (nao alteram control-flow),
idempotentes, e OFF por default (sem env = no-op), regra 6 do CLAUDE.md.
"""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
C1 = ROOT / "ppu_recomp_001.cpp"

s1 = C1.read_text(encoding="utf-8", errors="replace")

# --- [LDRSH] entry probe: func_0032109C ---
if "[LDRSH]" in s1:
    print("LDRSH already present")
else:
    old = """void func_0032109C(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0xB0, ctx->gpr[1]); ctx->gpr[1] += -0xB0;"""
    new = """void func_0032109C(ppu_context* ctx) {
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=(getenv("PS3_TRACE_LDRSH")||getenv("PS3_TRACE_TYMAP"))?1:0;}
          if(on){ static int n=0; if(n++<32)
            fprintf(stderr,"[LDRSH] #%d entry r3=0x%08X r4=0x%08X\\n", n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[4]); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + -0xB0, ctx->gpr[1]); ctx->gpr[1] += -0xB0;"""
    if s1.count(old) != 1:
        raise SystemExit(f"0032109C entry needle count={s1.count(old)} (expected 1)")
    s1 = s1.replace(old, new, 1)
    print("LDRSH entry probe added")

# --- [SHADERSRC] N=<n>: func_003CC208, logo apos a leitura do count no stream ---
if "[SHADERSRC]" in s1:
    print("SHADERSRC already present")
else:
    old = """        func_001856A8(ctx); DRAIN_TRAMPOLINE(ctx);
        /* nop */;
        ctx->gpr[25] = vm_read32(ctx->gpr[1] + 0x70);
        ctx->gpr[0] = (int64_t)(int32_t)((uint32_t)0x4EC << 16);
        ctx->gpr[30] = ppc_rldicl(ctx->gpr[26], 0, 32);
        ctx->gpr[0] = ctx->gpr[0] | 0x4EC4;"""
    new = """        func_001856A8(ctx); DRAIN_TRAMPOLINE(ctx);
        /* nop */;
        ctx->gpr[25] = vm_read32(ctx->gpr[1] + 0x70);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=(getenv("PS3_TRACE_SHADERSRC")||getenv("PS3_TRACE_TYMAP"))?1:0;}
          if(on){ static int n=0; if(n++<32)
            fprintf(stderr,"[SHADERSRC] #%d N=%d obj=0x%08X\\n", n,(int32_t)ctx->gpr[25],(uint32_t)ctx->gpr[26]); fflush(stderr);} }
        ctx->gpr[0] = (int64_t)(int32_t)((uint32_t)0x4EC << 16);
        ctx->gpr[30] = ppc_rldicl(ctx->gpr[26], 0, 32);
        ctx->gpr[0] = ctx->gpr[0] | 0x4EC4;"""
    if s1.count(old) != 1:
        raise SystemExit(f"003CC208 count-read needle count={s1.count(old)} (expected 1)")
    s1 = s1.replace(old, new, 1)
    print("SHADERSRC N= probe added")

C1.write_text(s1, encoding="utf-8", newline="\n")
print("OK patch_ldrsh_shadersrc_entry")
