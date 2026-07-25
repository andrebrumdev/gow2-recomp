#!/usr/bin/env python3
"""Gated probe: what does func_002C0FA0 (estado 3, ramo audio) ver em obj+0x720
via func_0045B2A8, e o que devolve, a cada tick que o gate e' avaliado?

WHY
---
Task 3b (gow2-recomp/.superpowers/sdd/task-3-brief.md), disparada porque a
Task 3 (arm do EOS atrasado ate st620>=5, gow2-recomp/movie_eos_arm.c commit
e5e1495) deu RED: 60s de boot com o recipe canonico, st620 fica preso em 3 a
corrida inteira (nunca chega a 4), [cellVdec] Open/StartSeq continuam em 0, e
o site=002C069C (estado 4, sonda PS3_TRACE_SMPD ja existente) nunca dispara
nenhuma vez -- ver notes/2026-07-21-wad-trigger-g4.md secc. 11 (Task 1/3) para
o historial completo.

A RE estatica da secc. 3 dessa nota ja tinha mapeado a cadeia entre o estado 3
(func_002C05F8, +0x744==0) e o estado 4 (func_002C069C):

    func_002C0688 (le +0x746; ==0 -> func_002C0FA0; !=0 -> avanca direto p/ 4)
      -> func_002C0FA0:
             gpr3 = vm_read32(obj+0x720)         # handle de audio (snd_stream)
             gpr3 = func_0045B2A8(gpr3)           # resolve geracional + le +0x1B8
             if gpr3 == 0 (literal)  -> func_002C0614  (PARK, fica em 3)
             else (inclui -1!)       -> func_002C0694  (AVANCA p/ estado 4)

Ou seja, o teste real e' "gpr3==0 literal para" -- um handle nao resolvido
devolve -1 (que AVANCA, nao para). Se o estado fica preso em 3 a corrida
inteira, so' ha duas explicacoes possiveis: (a) o handle NUNCA resolve para
0/invalido de um jeito que ainda assim devolve 0 literal (nao -1), ou (b) o
handle resolve e a sessao encontrada tem +0x1B8==0 persistentemente. A RE por
si so' nao decide qual -- precisa do valor real medido em boot. Esta sonda
imprime os tres campos relevantes (h720, rc, f746) mais o st620 corrente em
CADA chamada a func_0045B2A8 dentro de func_002C0FA0, para classificar A3 /
A3b / A3c (ver task-3-brief.md, seccao Task 3b).

PLACEMENT -- ARMADILHA DE CODIGO MORTO
---------------------------------------
`func_0045B2A8(ctx); DRAIN_TRAMPOLINE(ctx);` aparece LITERALMENTE 15 vezes no
lift (ppu_recomp_001/002/005/013/021.cpp) porque o lifter arrasta blocos
adjacentes na memoria original como "codigo morto" apos um `return` sempre que
outra funcao lifted comeca logo a seguir a um site de chamada identico na
imagem original. 14 dessas 15 ocorrencias estao IMEDIATAMENTE a seguir a um
`{ g_trampoline_fn = ...func_002C0620; return; }` -- ou seja, sao inalcancaveis
(dead code dentro de OUTRAS funcoes). SO' a ocorrencia dentro da propria
`func_002C0FA0` (ppu_recomp_002.cpp) e' viva. Por isso a NEEDLE abaixo inclui a
assinatura da funcao (`void func_002C0FA0(...) {`) como prefixo -- garante que
o replace (que so' actua no primeiro match por ficheiro) cai no site vivo, nao
numa das 14 copias mortas. Confirmado por grep antes de escrever este ficheiro:
`grep -n "func_0045B2A8(ctx); DRAIN_TRAMPOLINE" ppu_recomp_*.cpp` = 15 hits,
14 precedidos por `return;`.

Gated por PS3_TRACE_AUDGATE, OFF por default. Read-only (so' fprintf; nenhum
vm_write, nenhum forge de st620/+0x744/+0x720/+0x1B8). Idempotente (marker
AUDGATE-PROBE). Fprintf verbatim conforme o brief da Task 3b Step 1.
"""
from pathlib import Path
import sys

MARKER = "AUDGATE-PROBE"

ROOT = (Path(sys.argv[1]) if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "recomp_macos_v2")

# Assinatura + as duas linhas que levam ao gate -- ancorar na assinatura evita
# as 14 copias mortas de "func_0045B2A8(ctx); DRAIN_TRAMPOLINE(ctx);" (ver
# docstring). So' existe UM "void func_002C0FA0(...) {" em todo o lift.
NEEDLE = (
    "void func_002C0FA0(ppu_context* ctx) {\n"
    "        ctx->gpr[3] = vm_read32(ctx->gpr[30] + 0x720);\n"
    "        func_0045B2A8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
)

INSERT = (
    "void func_002C0FA0(ppu_context* ctx) {\n"
    "        ctx->gpr[3] = vm_read32(ctx->gpr[30] + 0x720);\n"
    "        func_0045B2A8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    "        /* " + MARKER + ": Task 3b -- classifica A3/A3b/A3c (obj=ctx->gpr[30]) */\n"
    "        { static int _on=-1; if(_on<0){extern char* getenv(const char*);\n"
    "            const char* _e=getenv(\"PS3_TRACE_AUDGATE\"); _on=(_e&&*_e&&*_e!='0')?1:0;}\n"
    "          if(_on){ static int _n=0; if(_n++<4000){\n"
    "            fprintf(stderr, \"[AUDGATE] h720=0x%08X rc=%d f746=%u st=%u\\n\",\n"
    "                (unsigned)vm_read32(ctx->gpr[30]+0x720), (int)(int32_t)ctx->gpr[3],\n"
    "                (unsigned)vm_read8(ctx->gpr[30]+0x746), (unsigned)vm_read32(ctx->gpr[30]+0x620));\n"
    "            fflush(stderr); } } }\n"
)


def patch_file(p: Path) -> str:
    t = p.read_text(encoding="utf-8", errors="replace")
    if MARKER in t:
        return "ALREADY"
    if NEEDLE not in t:
        return "SKIP"
    t = t.replace(NEEDLE, INSERT, 1)
    p.write_text(t, encoding="utf-8")
    return "APPLIED"


def main() -> int:
    files = sorted(ROOT.glob("ppu_recomp_*.cpp"))
    if not files:
        print("nenhum ppu_recomp_*.cpp em %s" % ROOT)
        return 1
    any_hit = False
    for p in files:
        r = patch_file(p)
        if r != "SKIP":
            any_hit = True
            print("%s: %s" % (p.name, r))
    if not any_hit:
        print("SKIP: needle not found (func_002C0FA0)")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
