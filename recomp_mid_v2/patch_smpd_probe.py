#!/usr/bin/env python3
"""PS3_TRACE_SMPD -- sonda discriminadora B vs H-hook (plano EOS, Task 1).

WHY
---
Depois do wall [B] (st620 "parece" parar em 3, WADs nunca abrem), falta saber
se o arme do read-hook de EOS (`g_movie_eos_ea`, ver
`../../ps3recomp/runtime/ppu/ppu_loader.cpp:722-726`) chega mesmo a ser LIDO
com valor 1 por algum dos gates reais da FSM (classe B: fix no consumidor) ou
se nenhum gate o ve' (classe H-hook: o hook nao cobre o leitor certo). Esta
sonda e' SO' leitura: nunca escreve `obj+0x620` (st620) nem `obj+0x744`.

O QUE O BRIEF ORIGINAL ERRAVA (RE re-verificada nesta task, grep por
`vm_read8(ctx->gpr[30] + 0x744)` no lift `recomp_macos_v2/ppu_recomp_*.cpp`)
-------------------------------------------------------------------------
O brief listava `func_002C0508 / func_002C0570 / func_002C05C8` como os 3
leitores de `+0x744`. Essa lista e' aproximada e parcialmente errada:

  * `func_002C0508` (o "pump", `ppu_recomp_001.cpp:36482`) despacha por
    JUMP TABLE lendo **st620** (`obj+0x620`), nao `+0x744`. O `+0x744` que o
    grep acha DENTRO do corpo textual desta funcao (`:36550`) fica DEPOIS de
    um `ps3_indirect_tail(ctx); return;` incondicional (`:36525`) sem label
    a apontar para ali -- e' codigo morto (artefacto do sweep linear do
    lifter sobre os bytes da tabela de saltos + o handler que se segue no
    binario original). Nunca executa. O mesmo padrao repete-se em
    `func_002C0570` (`ppu_recomp_002.cpp:224667`, e' o clone re-entrante do
    pump chamado por `func_002C0614` quando `obj+0x71C!=0`): a leitura de
    `+0x744` em `:224703` e' igualmente codigo morto a seguir ao seu proprio
    `ps3_indirect_tail`.
  * `func_002C05C8` (`ppu_recomp_002.cpp:224742`) o brief acertou o endereco
    por aproximacao, mas nao percebeu o papel: NAO e' o handler do estado 3
    (isso e' `func_002C05F8`, ja coberto por `patch_st3_probe.py` /
    `PS3_TRACE_ST3` -- nao voltar a sondar). E' a funcao de RETRY chamada por
    `func_002C07D8` (ver abaixo) quando o estado 1 ainda nao viu `+0x744!=0`;
    o SEU corpo (repete a mesma logica de `func_002C05F8`: poll de
    `func_002B4224`, escreve st620=2->3, so' DEPOIS le' `+0x744`) e' RE-
    ALCANCAVEL a cada retry -- portanto e' um gate real, so' que por acaso.
  * O leitor que faltava ao brief por completo: `func_002C07D8`
    (`ppu_recomp_001.cpp:36760`), o handler do ESTADO 1 (jump table:
    st620==1 -> 0x2C07D8). Lê `+0x744` como primeira instrucao; `!=0` avanca
    (st620=2->3, trampolim para `func_002C05F8`); `==0` chama
    `func_002C05C8` (o retry acima). Este e' o gate mais cedo na FSM.

Grep completo por `vm_read8(ctx->gpr[30] + 0x744)` no lift (2026-07-20, commit
`80e44fa` + patches desta sessao) da' 10 ocorrencias em 4 ficheiros. Deste
total, 3 sao sondados aqui como gates de leitura (Sites A/B/E), 1 ja' esta'
sondado por `patch_st3_probe.py` (002C05F8), 2 sao codigo morto (mesmo
padrao "depois de indirect_tail sem label", dentro de
`func_002C0508`/`func_002C0570` -- nunca executam) e os ultimos 4
(`func_002C0788`/estado 10, `func_002C07F8`/estado 11 em
`ppu_recomp_001.cpp`, mais os espelhos standalone
`func_002C0804`/`ppu_recomp_005.cpp:54714` e
`func_002C082C`/`ppu_recomp_021.cpp:538089`, clones re-entraveis do loop de
"playing" do estado 11) ficam FORA do escopo -- nao instrumentados porque a
cadeia de avanco 4->10->11 ou pausa em qualquer um deles sem log directo; se
uma task futura precisar de granularidade ali, sao candidatos naturais a
Sites F+.

SITES SONDADOS (5, read-only)
------------------------------
| Site | Funcao        | Ficheiro:linha (lift actual)   | O que loga |
|------|---------------|---------------------------------|------------|
| A    | func_002C07D8 | ppu_recomp_001.cpp:36761        | [EOSGATE] site=002C07D8 val + branch |
| B    | func_002C05C8 | ppu_recomp_002.cpp:224755       | [EOSGATE] site=002C05C8 val + branch |
| C    | func_002BFF88 | ppu_recomp_001.cpp:36203 (antes)| [STOP] SMPD prev_st620 + r3/r4 |
| D    | func_002BFF88 | ppu_recomp_001.cpp:36147 (apos) | [STOPENTRY] obj + st620 (qualquer ramo) |
| E    | func_002C069C | ppu_recomp_001.cpp:36660 (apos) | [EOSGATE] site=002C069C val + branch |

Site C (MovieStop): o ramo comum `loc_002C0048:` (com ou sem teardown de
1..0xA) faz um broadcast 'SMPD' (0x534D5044) / tamanho 0x1C / param 0 via
`func_0043FF30`, ANTES de escrever `st620=0`. No lift, os registos r3..r9
desse broadcast sao carregados umas linhas ANTES do proprio write (agenda-
mento tipico de compilador PPC) -- por isso r3/r4 ja' valem 'SMPD'/0x1C no
ponto da sonda, sem qualquer escrita extra. O valor "anterior" de st620 nao
sobrevive em nenhum registo nesse ponto (gpr[0] ja foi reciclado para 0, o
valor a escrever) -- a sonda faz UMA leitura extra (`vm_read32`) do proprio
`obj+0x620` ainda-nao-escrito, puramente para logar; nao toca em `ctx->gpr`
nem precede/substitui o write real, que fica intacto.

func_002C05F8 (estado 3, `ppu_recomp_001.cpp:36595`) MANTEM-SE sondado so'
por `patch_st3_probe.py` / `PS3_TRACE_ST3` -- nao duplicado aqui.

SITES D/E (adicionados DEPOIS do GREEN #1 empirico -- ver abaixo)
------------------------------------------------------------------
O GREEN #1 (arm real, `PS3_MOVIE_DONE_MS=5000`, 40s) revelou um buraco na
cobertura acima: o read-hook do motor (`[MOVIEEOS] read-hook HIT`, log
INCONDICIONAL do proprio `ppu_loader.cpp`, nao desta sonda) disparou 3x logo
a seguir ao arme, e o sampler independente (`movie_eos_arm.c`, `[MOVIEFSM]`)
registou `st620 3 -> 0` pouco depois -- ou seja, ALGUM Stop aconteceu. Mas
nem os Sites A/B (cada um so' dispara UMA vez, na transicao inicial 0->1->3,
muito antes dos 5s do arme -- estrutural, nao e' questao de cap) nem o Site C
(so' cobre o ramo comum `1..0xA` de `func_002BFF88`) nem o ST3-PROBE
pre-existente (400 capado, EXAUSTO 10 linhas ANTES do arme neste log -- o
"trap" que o brief avisava: `grep -n 'arming EOS'` = linha 22250,
`grep -n ST3-tag | tail -1` = linha 22240) mostraram qualquer `val=1` nem
qualquer `[STOP]`. RE de `func_002BFF88` mostra que ela tem um 3o ramo, so'
tomado quando `st620==0xB` (11, "playing"): trampolina para `func_002C008C`
(`ppu_recomp_001.cpp:36221`), que por sua vez trampolina para
`func_002BFFE0`/`func_002BFFF4` (`ppu_recomp_002.cpp:224556`/`224604`) --
MESMO padrao de broadcast SMPD + write st620=0 do Site C, so' que num sitio
que a task original nao listava (porque a RE estatica que gerou o brief nao
tinha como prever que o arme empurraria a FSM ate' ao estado 0xB antes do
Stop). Para fechar o buraco SEM reescrever os Sites A/B/C nem tocar
`patch_st3_probe.py`, dois sites novos, ambos read-only:

  * Site D -- `func_002BFF88`, logo a seguir a' PRIMEIRA leitura de st620
    (entrada da funcao, `ctx->gpr[0] = vm_read32(ctx->gpr[31] + 0x620);`,
    ANTES de qualquer branch). Loga TODAS as chamadas ao MovieStop,
    qualquer que seja o ramo tomado a seguir -- inclui o `st620==0xB` que o
    Site C (no write comum `1..0xA`) nao ve.
  * Site E -- `func_002C069C` (estado 4, `ppu_recomp_001.cpp:36659`), o
    PRIMEIRO gate de `+0x744` a jusante do estado 3 na jump table. Se isto
    mostrar `val=1`, e' prova directa e nao-capada (ao contrario do
    ST3-PROBE) de que a FSM avancou por causa do arme.

AMBIGUIDADE DO GATE ENV (resolvida por instrucao explicita desta task)
-----------------------------------------------------------------------
Nome novo `PS3_TRACE_SMPD` (NAO reutiliza `PS3_TRACE_ST3`), para as duas
sondas serem controlaveis independentemente. Marker: `SMPD-PROBE`. OFF por
default (sem a env, zero linhas `[EOSGATE]`/`[STOP]` -- baseline identico).

ANCORAGEM (por que region-scoped em vez de `str.replace` piano no ficheiro
inteiro, ao contrario de `patch_st3_probe.py` mas IGUAL a
`patch_fios_sticky.py`, o script idempotente mais recente deste dir)
-----------------------------------------------------------------------
O corpo de `func_002C05C8` (site B) e' TEXTUALMENTE IDENTICO ao codigo morto
que sobra dentro de `func_002C0570` a seguir ao seu `ps3_indirect_tail`
(mesmo bytes de guest, `0x2C05C8`-`0x2C0614`, duplicados pelo lifter -- ver
acima). As 3 linhas que terminam na leitura de `+0x744` aparecem 2x em
`ppu_recomp_002.cpp`: uma vez (morta) dentro de `func_002C0570`, outra vez
(real) como o corpo de `func_002C05C8`. Um `str.replace(needle, insert, 1)`
ingenuo no ficheiro inteiro apanharia a ocorrencia ERRADA (a morta, que nunca
loga nada) sem sequer falhar. Por isso as insercoes sao aplicadas dentro da
REGIAO da funcao-alvo (assinatura ate' ao proximo `void func_`), com
`region.count(ancora)` a exigir exactamente 1 dentro dessa regiao -- se for
0 ou >1, `SystemExit` (fail loud; nunca forcar). E' "`str.replace` sobre uma
fatia" do texto, nao `re.sub` (escapes de regex corrompem C literal).

Idempotente por site (nao por ficheiro inteiro): cada `_edit_after`/
`_edit_before` verifica se `ancora+bloco` (ou `bloco+ancora`) ja' esta' na
regiao antes de tentar aplicar -- uma 2a corrida, ou uma corrida parcial
anterior interrompida a meio, fica ALREADY site a site e completa o que
faltar, em vez de um unico gate "MARKER in ficheiro inteiro" que esconderia
uma aplicacao parcial.

Uso:  patch_smpd_probe.py [DIR_DE_LIFT]     (default: ../recomp_macos_v2)
Reaplicado por ../apply_all_patches.sh apos cada re-lift (nao tem check
registado em apply_all_patches.sh -- e' sonda pura, sem efeito funcional,
mesmo precedente de patch_st3_probe.py, que tambem nao tem).
"""
from pathlib import Path
import sys

MARKER = "SMPD-PROBE"

ROOT = (Path(sys.argv[1]) if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "recomp_macos_v2")

# ---- Site A: func_002C07D8 (estado 1) ---------------------------------------
SITE_A_FUNC = "func_002C07D8"
SITE_A_SIG = "void " + SITE_A_FUNC + "(ppu_context* ctx) {\n"
SITE_A_ANCHOR = "        ctx->gpr[0] = vm_read8(ctx->gpr[30] + 0x744);\n"
SITE_A_BLOCK = (
    "        /* " + MARKER + ": gate EOS do estado 1 (func_002C07D8) -- brief nao listava este site */\n"
    "        { static int _on=-1; if(_on<0){extern char* getenv(const char*);\n"
    "            const char* _e=getenv(\"PS3_TRACE_SMPD\"); _on=(_e&&*_e&&*_e!='0')?1:0;}\n"
    "          if(_on){ static int _n=0; if(_n++<400){\n"
    "            fprintf(stderr,\"[EOSGATE] site=002C07D8 obj=0x%08X ea=0x%08X val=%u branch=%s\\n\",\n"
    "              (uint32_t)ctx->gpr[30],(uint32_t)(ctx->gpr[30]+0x744),(unsigned)ctx->gpr[0],\n"
    "              ((unsigned)ctx->gpr[0]!=0)?\"adv\":\"wait\");\n"
    "            fflush(stderr); } } }\n"
)

# ---- Site B: func_002C05C8 (retry do estado 1) -------------------------------
SITE_B_FUNC = "func_002C05C8"
SITE_B_SIG = "void " + SITE_B_FUNC + "(ppu_context* ctx) {\n"
SITE_B_ANCHOR = (
    "        ctx->gpr[0] = (int64_t)(int32_t)(3);\n"
    "        vm_write32(ctx->gpr[30] + 0x620, ctx->gpr[0]);\n"
    "        ctx->gpr[0] = vm_read8(ctx->gpr[30] + 0x744);\n"
)
SITE_B_BLOCK = (
    "        /* " + MARKER + ": gate EOS de func_002C05C8 (retry do estado 1 chamado por 002C07D8 quando val==0) */\n"
    "        { static int _on=-1; if(_on<0){extern char* getenv(const char*);\n"
    "            const char* _e=getenv(\"PS3_TRACE_SMPD\"); _on=(_e&&*_e&&*_e!='0')?1:0;}\n"
    "          if(_on){ static int _n=0; if(_n++<400){\n"
    "            fprintf(stderr,\"[EOSGATE] site=002C05C8 obj=0x%08X ea=0x%08X val=%u branch=%s\\n\",\n"
    "              (uint32_t)ctx->gpr[30],(uint32_t)(ctx->gpr[30]+0x744),(unsigned)ctx->gpr[0],\n"
    "              ((unsigned)ctx->gpr[0]!=0)?\"adv\":\"wait\");\n"
    "            fflush(stderr); } } }\n"
)

# ---- Site C: func_002BFF88 (MovieStop) ---------------------------------------
SITE_C_FUNC = "func_002BFF88"
SITE_C_SIG = "void " + SITE_C_FUNC + "(ppu_context* ctx) {\n"
SITE_C_ANCHOR = "        vm_write32(ctx->gpr[31] + 0x620, ctx->gpr[0]);\n"
SITE_C_BLOCK = (
    "        /* " + MARKER + ": MovieStop antes do write st620=0 (r3/r4 ja setados p/ broadcast SMPD/0x1C) */\n"
    "        { static int _on=-1; if(_on<0){extern char* getenv(const char*);\n"
    "            const char* _e=getenv(\"PS3_TRACE_SMPD\"); _on=(_e&&*_e&&*_e!='0')?1:0;}\n"
    "          if(_on){ static int _n=0; if(_n++<400){\n"
    "            uint32_t _prev_st620 = (uint32_t)vm_read32(ctx->gpr[31] + 0x620);\n"
    "            fprintf(stderr,\"[STOP] SMPD obj=0x%08X prev_st620=%u r3=0x%08X r4=0x%08X ->0\\n\",\n"
    "              (uint32_t)ctx->gpr[31], _prev_st620, (uint32_t)ctx->gpr[3], (uint32_t)ctx->gpr[4]);\n"
    "            fflush(stderr); } } }\n"
)

# ---- Site D: func_002BFF88, entrada (ANY branch) -----------------------------
# Mesma funcao do Site C, ancora DIFERENTE (a 1a leitura de st620, antes de
# qualquer branch) -- ve TAMBEM o ramo st620==0xB que trampolina para
# func_002C008C e nunca passa pelo write comum onde o Site C esta.
SITE_D_FUNC = SITE_C_FUNC
SITE_D_ANCHOR = "        ctx->gpr[0] = vm_read32(ctx->gpr[31] + 0x620);\n"
SITE_D_BLOCK = (
    "        /* " + MARKER + ": entrada do MovieStop (func_002BFF88), TODOS os ramos (<1 / 1..0xA / 0xB) */\n"
    "        { static int _on=-1; if(_on<0){extern char* getenv(const char*);\n"
    "            const char* _e=getenv(\"PS3_TRACE_SMPD\"); _on=(_e&&*_e&&*_e!='0')?1:0;}\n"
    "          if(_on){ static int _n=0; if(_n++<400){\n"
    "            fprintf(stderr,\"[STOPENTRY] func_002BFF88 obj=0x%08X st620=%u\\n\",\n"
    "              (uint32_t)ctx->gpr[31],(unsigned)ctx->gpr[0]);\n"
    "            fflush(stderr); } } }\n"
)

# ---- Site E: func_002C069C (estado 4) -----------------------------------------
# Primeiro gate de +0x744 a jusante do estado 3. Adicionado so' depois do
# GREEN #1 (ver docstring) para ter pelo menos UM gate repetivel, nao-capado
# e fora da FSM de estado 1, que possa mostrar val=1 directamente.
SITE_E_FUNC = "func_002C069C"
SITE_E_SIG = "void " + SITE_E_FUNC + "(ppu_context* ctx) {\n"
SITE_E_ANCHOR = "        ctx->gpr[0] = vm_read8(ctx->gpr[30] + 0x744);\n"
SITE_E_BLOCK = (
    "        /* " + MARKER + ": gate EOS do estado 4 (func_002C069C), 1o a jusante do estado 3 */\n"
    "        { static int _on=-1; if(_on<0){extern char* getenv(const char*);\n"
    "            const char* _e=getenv(\"PS3_TRACE_SMPD\"); _on=(_e&&*_e&&*_e!='0')?1:0;}\n"
    "          if(_on){ static int _n=0; if(_n++<400){\n"
    "            fprintf(stderr,\"[EOSGATE] site=002C069C obj=0x%08X ea=0x%08X val=%u branch=%s\\n\",\n"
    "              (uint32_t)ctx->gpr[30],(uint32_t)(ctx->gpr[30]+0x744),(unsigned)ctx->gpr[0],\n"
    "              ((unsigned)ctx->gpr[0]!=0)?\"adv\":\"wait\");\n"
    "            fflush(stderr); } } }\n"
)


def _region(t, func):
    """(i, end, region) da funcao; region vai da assinatura ao proximo 'void func_'."""
    sig = "void " + func + "(ppu_context* ctx) {\n"
    i = t.find(sig)
    if i < 0:
        return -1, -1, ""
    j = t.find("\nvoid func_", i + len(sig))
    end = j if j > i else len(t)
    return i, end, t[i:end]


def _edit_after(t, func, anchor, block, tag):
    i, end, region = _region(t, func)
    if i < 0:
        return t, "%s: SKIP(func)" % tag
    if anchor + block in region:
        return t, "%s: ALREADY" % tag
    c = region.count(anchor)
    if c != 1:
        raise SystemExit(
            "patch_smpd_probe: ancora de %s aparece %dx em %s (esperado 1) -- "
            "shape do lift mudou; reveja a needle antes de forcar" % (tag, c, func))
    region = region.replace(anchor, anchor + block, 1)
    return t[:i] + region + t[end:], "%s: APPLIED" % tag


def _edit_before(t, func, anchor, block, tag):
    i, end, region = _region(t, func)
    if i < 0:
        return t, "%s: SKIP(func)" % tag
    if block + anchor in region:
        return t, "%s: ALREADY" % tag
    c = region.count(anchor)
    if c != 1:
        raise SystemExit(
            "patch_smpd_probe: ancora de %s aparece %dx em %s (esperado 1) -- "
            "shape do lift mudou; reveja a needle antes de forcar" % (tag, c, func))
    region = region.replace(anchor, block + anchor, 1)
    return t[:i] + region + t[end:], "%s: APPLIED" % tag


def patch_file(p: Path):
    t = p.read_text(encoding="utf-8", errors="replace")
    if (SITE_A_SIG not in t and SITE_B_SIG not in t and SITE_C_SIG not in t
            and SITE_E_SIG not in t):
        return "SKIP", (False, False, False, False)
    orig = t
    notes = []
    found = [False, False, False, False]  # A, B, C+D (func_002BFF88), E
    if SITE_A_SIG in t:
        found[0] = True
        t, s = _edit_after(t, SITE_A_FUNC, SITE_A_ANCHOR, SITE_A_BLOCK, "eosgate-07D8")
        notes.append(s)
    if SITE_B_SIG in t:
        found[1] = True
        t, s = _edit_after(t, SITE_B_FUNC, SITE_B_ANCHOR, SITE_B_BLOCK, "eosgate-05C8")
        notes.append(s)
    if SITE_C_SIG in t:
        found[2] = True
        t, s = _edit_before(t, SITE_C_FUNC, SITE_C_ANCHOR, SITE_C_BLOCK, "stop-2bff88-write")
        notes.append(s)
        t, s = _edit_after(t, SITE_D_FUNC, SITE_D_ANCHOR, SITE_D_BLOCK, "stop-2bff88-entry")
        notes.append(s)
    if SITE_E_SIG in t:
        found[3] = True
        t, s = _edit_after(t, SITE_E_FUNC, SITE_E_ANCHOR, SITE_E_BLOCK, "eosgate-069C")
        notes.append(s)
    if t != orig:
        p.write_text(t, encoding="utf-8", newline="\n")
        return "APPLIED | " + " ; ".join(notes), tuple(found)
    return "ALREADY | " + " ; ".join(notes), tuple(found)


def main() -> int:
    files = sorted(ROOT.glob("ppu_recomp_*.cpp"))
    if not files:
        print("nenhum ppu_recomp_*.cpp em %s" % ROOT)
        return 1
    any_hit = False
    seen = [False, False, False, False]  # func_002C07D8 / 002C05C8 / 002BFF88 / 002C069C
    for p in files:
        r, found = patch_file(p)
        seen = [s or f for s, f in zip(seen, found)]
        if r != "SKIP":
            any_hit = True
            print("%s: %s" % (p.name, r))
    missing = [name for name, ok in
               zip((SITE_A_FUNC, SITE_B_FUNC, SITE_C_FUNC, SITE_E_FUNC), seen) if not ok]
    if missing:
        raise SystemExit(
            "patch_smpd_probe: funcao(oes) nunca encontrada(s) em nenhum "
            "ppu_recomp_*.cpp: %s (shape do lift mudou?) -- reveja antes de forcar"
            % ", ".join(missing))
    if not any_hit:
        print("SKIP: nada para aplicar (tudo ja ALREADY nao deveria cair aqui)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
