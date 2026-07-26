#!/usr/bin/env python3
"""Gera o PATCH_CATALOG.tsv (Fase 4, Plano 04-01, D-4.3/D-4.4).

O ROADMAP falava em 73/71 patches; a contagem real medida contra o corpus que
`apply_all_patches.sh` de facto corre (../gow2-recomp/recomp_mid_v2, NAO o
espelho subtree atrasado games/gow2/recomp_mid_v2 com 75/87 ficheiros) e' 87.
Sem um catalogo DERIVADO, "os PROBE ficam fora do gate" e' uma frase sem
mecanismo: alguem decide a olho, diverge no primeiro dia, e um patch novo
nunca e' classificado -- fica invisivel ao gate, nao "fora dele por decisao".

Algoritmo de classificacao (4 ramos, na ordem, o primeiro que casar decide --
ver 04-CONTEXT.md e 04-01-PLAN.md para a medicao completa contra o corpus):

  1. O ficheiro inteiro (incluindo o docstring) contem a frase literal
     "inventar comportamento" -> PROBE / orfao-sem-fonte. Medido: casa em
     exactamente 2 ficheiros (os dois CE03C verificadores puros
     auto-declarados permanentemente insatisfazveis, regra 4 do CLAUDE.md).
  2. Senao, o ficheiro contem a frase literal "Diagnostic only" -> PROBE /
     diagnostico. Medido: casa em exactamente 1 ficheiro
     (patch_cc9d0_live_yield.py).
  3. Senao, o NOME casa `_probe.py$` ou `_trace.py$` E o CORPO do ficheiro
     SEM o docstring do modulo nao contem nenhum token de despacho
     (DISPATCH_RE) -> PROBE / diagnostico. Se o nome sugerir probe/trace MAS
     o corpo (fora do docstring) tiver um token de despacho, a classe e'
     FUNCIONAL / dispatch-fix -- a classe e' propriedade do comportamento,
     nunca do nome do script (regra de desempate medida contra
     patch_2b0fb4_trace.py / patch_a1_chain_probe.py, que tem sufixo
     _trace/_probe mas SAO FUNCIONAL).
  4. Tudo o resto -> FUNCIONAL, subclasse derivada do primeiro token do
     dicionario SUBCLASS_TOKENS que aparecer no nome do ficheiro, senao
     "misc".

Deteccao ESCREVE/VERIFICA e' sempre por AST (ast.walk), nunca por grep de
substring: um grep ingenuo sobre o ficheiro inteiro da' falso-positivo dentro
do PROPRIO docstring de patch_ce03c_wait_idle_f2b_movie.py, que contem a
string "write_text" em prosa ("Este ficheiro nao escreve nada (0
write_text/open('w'))"). O mesmo cuidado vale para DISPATCH_RE no ramo 3:
patch_fios_open_probe.py MENCIONA "g_trampoline_fn = func_002B43DC" no
docstring (narrando um bug historico) sem o corpo alguma vez o escrever --
por isso o ramo 3 usa strip_docstring() antes de aplicar DISPATCH_RE.

Task 1 (04-01-PLAN.md): apenas classify() e as funcoes de suporte, testadas
fim-a-fim contra 6 patches reais representando os 4 ramos (Task 2 estende
este ficheiro com a geracao do PATCH_CATALOG.tsv contra os 87 reais).
"""
from __future__ import annotations

import ast
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Tokens de despacho real: OPD deref (ps3_call_opd), trampolim global
# (g_trampoline_fn =), ou retorno imediato apos indirect-call (padrao de
# tail-skip). Um patch cujo corpo escreve isto converte comportamento real,
# nao e' diagnostico puro -- independentemente do nome do ficheiro.
DISPATCH_RE = re.compile(
    r"ps3_call_opd\(|g_trampoline_fn =|ps3_indirect_call\(ctx\); *return;"
)

PROBE_NAME_RE = re.compile(r"_probe\.py$|_trace\.py$")

# Primeiro token do nome do ficheiro que casar decide a subclasse FUNCIONAL
# (ramo 4). Ordem importa -- "groupend"/"opdisp" mapeiam para "opd" antes de
# qualquer token generico, "bctr" mapeia para "dispatch".
SUBCLASS_TOKENS: list[tuple[str, str]] = [
    ("opd", "opd"),
    ("guard", "guard"),
    ("wadld", "wadld"),
    ("fios", "fios"),
    ("type15", "type15"),
    ("factory", "factory"),
    ("jumptable", "jumptable"),
    ("tymap", "tymap"),
    ("tydisp", "tymap"),
    ("host_res", "host"),
    ("zz_host", "host"),
    ("shadersrc", "shader"),
    ("ldrsh", "shader"),
    ("groupend", "opd"),
    ("opdisp", "opd"),
    ("bctr", "dispatch"),
]


def has_write_call(tree: ast.AST) -> bool:
    """True se o AST tem uma chamada real de escrita (nunca por substring).

    Casa `<algo>.write_text(...)`, `<algo>.write(...)`, ou `os.replace(...)`/
    `os.rename(...)` explicitamente sobre o modulo `os`.
    """
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            attr = node.func.attr
            if attr in ("write_text", "write"):
                return True
            if attr in ("replace", "rename"):
                obj = node.func.value
                if isinstance(obj, ast.Name) and obj.id == "os":
                    return True
    return False


def strip_docstring(src: str, tree: ast.AST) -> str:
    """Devolve `src` sem o docstring do modulo (1a ocorrencia), se existir."""
    doc = ast.get_docstring(tree)
    if doc:
        return src.replace(doc, "", 1)
    return src


def subclasse(name: str) -> str:
    """Primeiro token de SUBCLASS_TOKENS presente em `name`; senao "misc"."""
    for token, label in SUBCLASS_TOKENS:
        if token in name:
            return label
    return "misc"


def classify(name: str, src: str) -> tuple[str, str, bool]:
    """Classifica um patch_*.py: devolve (classe, subclasse, no_gate).

    Funcao pura: nao faz IO alem do parse do proprio `src` recebido; chamada
    duas vezes com os mesmos argumentos devolve sempre o mesmo resultado.
    """
    tree = ast.parse(src, filename=name)

    # Ramo 1: verificador puro auto-declarado permanentemente insatisfazivel.
    if "inventar comportamento" in src:
        return ("PROBE", "orfao-sem-fonte", True)

    # Ramo 2: instrumentacao diagnostica auto-declarada.
    if "Diagnostic only" in src:
        return ("PROBE", "diagnostico", True)

    # Ramo 3: nome sugere probe/trace -- decide o CORPO (sem docstring), nao
    # o nome. Nome mente, comportamento manda.
    if PROBE_NAME_RE.search(name):
        stripped = strip_docstring(src, tree)
        if not DISPATCH_RE.search(stripped):
            return ("PROBE", "diagnostico", True)
        return ("FUNCIONAL", "dispatch-fix", False)

    # Ramo 4: tudo o resto.
    return ("FUNCIONAL", subclasse(name), False)
