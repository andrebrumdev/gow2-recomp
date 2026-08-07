#!/usr/bin/env python3
"""Sonda do PUSH e do POP do escopo da fabrica -- quem estabelece o escopo.

Porque existe (E49)
-------------------
A fabrica `0x400C6210` guarda um contexto numa pilha cujo cursor vive em
`this+0xC8`. `func_0039DA78` empurra, `func_0039DAB0` retira, e `func_0039E5A8`
(`vt[0x48]`) devolve o topo -- ou **0** se a pilha estiver vazia, por contrato.

O E49 mediu a particao dos 259 pedidos por chamador, e ela e' limpa:

    lr=0x0027C724  238  ok      FUN_0027c6f0
    lr=0x002553D8   10  ok      FUN_00255368
    lr=0x0042CA64    5  ok      FUN_0042ca14
    lr=0x0024E424    2  VAZIO   FUN_0024e198
    lr=0x0024E25C    1  VAZIO   FUN_0024e198
    lr=0x002B2DE0    1  VAZIO   FUN_002b2dd0
    lr=0x002A9A84    1  VAZIO   FUN_002a98e8
    lr=0x00237D38    1  VAZIO   FUN_00237cdc

Nenhum sitio e' misto: tres chamadores acertam 253 de 253, quatro falham 6 de 6.
Logo os que acertam correm DENTRO de um dos 176 escopos push/pop e os que
falham correm FORA de todos. Duas leituras, com fixes diferentes:

  1. FALTA O PUSH  -- o jogo devia ter empurrado antes destes quatro e, por
     razao nossa (HLE, ordem de init, caminho que nao corre), nao empurrou;
  2. SOBRA A CHAMADA -- estes quatro nao deviam correr aqui de todo.

Esta sonda nomeia quem abre e fecha os escopos. Com o `lr` do push ao lado do
`lr` do pedido, as duas leituras separam-se: se o push vem de um chamador que
tambem alcanca os quatro falhados, e' ordem; se vem de outro ramo que nunca os
alcanca, e' escopo em falta.

O que mede
----------
  PUSH  fab, cursor NOVO, valor guardado (r10), lr, tid
  POP   fab, cursor NOVO, lr, tid

`fab` e' `r3 - 0x48`: as duas funcoes somam 0x48 a' entrada, logo o `r3` no
sitio da escrita ja' nao e' o `this` original.

Nota sobre as agulhas: a do push ancora no label `loc_0039DA90` (unico no lift
inteiro -- o corpo sozinho aparece 581 vezes) e a do pop no trampolim para
`func_0039DAF4` (a linha do `vm_write8` sozinha aparece 5 vezes). Medido antes
de escrever, nao assumido.

Gate: `PS3_TRACE_SCOPE` (vazio ou "0" = OFF, default). Cap por
`PS3_TRACE_SCOPE_CAP` (default 800, `-1` = ilimitado; a corrida faz 353
escritas, logo o default cobre-a inteira com folga). Read-only.

Uso:  patch_39da78_scope_probe.py [DIR_DE_LIFT]
rc: 0 aplicado/ja aplicado; 2 se alguma agulha nao casou.
"""
import os
import sys
import glob

MARKER = "SCOPE-PROBE"

NEEDLE_PUSH = (
    "loc_0039DA90:\n"
    "        ctx->gpr[9] = vm_read8(ctx->gpr[3] + 0x80);\n"
    "        ctx->gpr[9] = ctx->gpr[9] + (int64_t)(1);\n"
    "        ctx->gpr[0] = (int64_t)(int8_t)ctx->gpr[9];\n"
    "        vm_write8(ctx->gpr[3] + 0x80, ctx->gpr[9]);\n"
)

BLOCK_PUSH = (
    "        /* " + MARKER + " push: quem abre o escopo da fabrica */\n"
    "        { static int _on=-1; if(_on<0){ extern char* getenv(const char*);\n"
    "            const char* _e=getenv(\"PS3_TRACE_SCOPE\");\n"
    "            _on=(_e&&*_e&&*_e!='0')?1:0; }\n"
    "          static int _cap=-2; if(_cap==-2){ extern char* getenv(const char*);\n"
    "            const char* _c=getenv(\"PS3_TRACE_SCOPE_CAP\");\n"
    "            _cap=(_c&&*_c)?atoi(_c):800; }\n"
    "          if(_on){ static int _n=0; if(_cap<0 || _n++<_cap){\n"
    "            unsigned long ps3_dbg_tid(void);\n"
    "            fprintf(stderr,\"[SCOPE] tid=%lu PUSH fab=0x%08X cursor=%d \"\n"
    "              \"val=0x%08X lr=0x%08X\\n\", ps3_dbg_tid(),\n"
    "              (uint32_t)ctx->gpr[3]-0x48u, (int)(int8_t)ctx->gpr[9],\n"
    "              (uint32_t)ctx->gpr[10], (uint32_t)ctx->lr);\n"
    "            fflush(stderr); } } }\n"
)

NEEDLE_POP = (
    "        if (((ctx->cr >> 0) & 8)) { g_trampoline_fn = (void(*)(void*))func_0039DAF4; return; }\n"
    "        ctx->gpr[11] = vm_read32((ctx->gpr[7] + ctx->gpr[11]));\n"
    "        vm_write8(ctx->gpr[3] + 0x80, ctx->gpr[10]);\n"
)

BLOCK_POP = (
    "        /* " + MARKER + " pop: quem fecha o escopo da fabrica */\n"
    "        { static int _on=-1; if(_on<0){ extern char* getenv(const char*);\n"
    "            const char* _e=getenv(\"PS3_TRACE_SCOPE\");\n"
    "            _on=(_e&&*_e&&*_e!='0')?1:0; }\n"
    "          static int _cap=-2; if(_cap==-2){ extern char* getenv(const char*);\n"
    "            const char* _c=getenv(\"PS3_TRACE_SCOPE_CAP\");\n"
    "            _cap=(_c&&*_c)?atoi(_c):800; }\n"
    "          if(_on){ static int _n=0; if(_cap<0 || _n++<_cap){\n"
    "            unsigned long ps3_dbg_tid(void);\n"
    "            fprintf(stderr,\"[SCOPE] tid=%lu POP  fab=0x%08X cursor=%d \"\n"
    "              \"lr=0x%08X\\n\", ps3_dbg_tid(),\n"
    "              (uint32_t)ctx->gpr[3]-0x48u, (int)(int8_t)ctx->gpr[10],\n"
    "              (uint32_t)ctx->lr);\n"
    "            fflush(stderr); } } }\n"
)


def patch_text(t):
    if MARKER in t:
        return t, "ALREADY", 0
    n = 0
    if NEEDLE_PUSH in t:
        t = t.replace(NEEDLE_PUSH, NEEDLE_PUSH + BLOCK_PUSH)
        n += 1
    if NEEDLE_POP in t:
        t = t.replace(NEEDLE_POP, NEEDLE_POP + BLOCK_POP)
        n += 1
    if not n:
        return t, "MISSING", 0
    return t, "APPLIED", n


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    lift = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "recomp_macos_v2")
    lift = os.path.abspath(lift)
    chunks = sorted(glob.glob(os.path.join(lift, "ppu_recomp_*.cpp")))
    if not chunks:
        print("ERRO: nenhum ppu_recomp_*.cpp em %s" % lift, file=sys.stderr)
        return 2
    applied = already = sites = 0
    for path in chunks:
        with open(path, "r", errors="replace") as fh:
            src = fh.read()
        out, state, n = patch_text(src)
        if state == "APPLIED":
            with open(path, "w") as fh:
                fh.write(out)
            applied += 1
            sites += n
            print("APPLIED  %-20s sites=%d" % (os.path.basename(path), n))
        elif state == "ALREADY":
            already += 1
            print("ALREADY  %s" % os.path.basename(path))
    if applied == 0 and already == 0:
        print("MISSING  agulhas do push/pop do escopo nao encontradas", file=sys.stderr)
        return 2
    # As duas agulhas vivem no MESMO chunk; menos de 2 sitios e' meia sonda,
    # e meia sonda mente por omissao exactamente como a PRODUCT mentiu (E45).
    if applied and sites < 2:
        print("AVISO: so' %d sitio(s) -- esperados 2 (push e pop)" % sites,
              file=sys.stderr)
        return 2
    print("patch_39da78_scope_probe: applied=%d already=%d sites=%d"
          % (applied, already, sites))
    return 0


if __name__ == "__main__":
    sys.exit(main())
