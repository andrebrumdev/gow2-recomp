#!/usr/bin/env python3
"""Gera o MANIFEST.tsv do baseline forense do lift (RDY-0, Task 1).

O lift do GoW2 e' gitignored e contem 1662 linhas de codigo host escritas a
mao que nao existem em mais lado nenhum. Este script inventaria tudo o que
tem de sobreviver a um re-lift:

  TAG    -- etiqueta [XXX] emitida por fprintf de instrumentacao/comportamento
  SYM    -- funcao host definida num preambulo injectado
  GLOBAL -- variavel global host definida num preambulo injectado

A referencia do preambulo PURO do lifter e' lift_baseline/preamble_pure.cpp
(131 linhas, byte-identico nos chunks 007..030 do lift de producao). Tudo o
que um preambulo tem a mais do que essa referencia e' injeccao nossa.

NOTA: ppu_recomp_002.cpp NAO serve de referencia -- tem 20 linhas injectadas.

Uso:
  python3 gen_manifest.py <LIFT_DIR> > MANIFEST.tsv     gerar
  python3 gen_manifest.py <LIFT_DIR> --verify FILE.tsv  verificar (rc=1 se falta)

A verificacao conta por marcador em TODOS os ppu_recomp_*.cpp do lift alvo,
nunca por chunk: o lifter actual produz 7 chunks contra os 31 do lift de
producao, logo qualquer gate indexado por numero de chunk parte-se sozinho.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
PURE = HERE / "preamble_pure.cpp"

TAG_RE = re.compile(r"\[[A-Z][A-Z0-9_-]{2,}\]")
PREFIX = r"(?:ps3|f2b|ty15|fact|snd|wavdrv)_[a-z0-9_]+"
SYM_RE = re.compile(r"\b(" + PREFIX + r")\s*\(")
GLOBAL_RE = re.compile(r"\b((?:g|k)_[a-z0-9_]+)\b")


def preamble_end(text: str) -> int:
    """Indice da 1a linha DEPOIS do preambulo -- ou seja, o inicio da 1a funcao.

    Desde a Fase 19 (XEN-04) uma funcao pode comecar em duas formas: a de
    sempre (`void func_X(ppu_context* ctx) {`) ou, quando declarada em
    `[[functions_override]]` com a emissao ligada, `PPC_FUNC_IMPL(func_X) {`.
    Conhecer so' a primeira dava um preambulo longo de mais sempre que a 1a
    funcao do chunk fosse uma com override -- e a fronteira e' o que separa o
    que se conta como preambulo do que se conta como corpo. Medido a
    2026-08-02: no lift desta fase o defeito NAO chegou a disparar (o
    MANIFEST_DEBT deu exactamente os mesmos 7/36 do baseline da Fase 18), o que
    o torna precisamente o tipo de bug dependente de ordem que so' aparece
    quando ja' custa caro. Corrigido antes disso."""
    for i, line in enumerate(text.splitlines()):
        if line.startswith(("void func_", "PPC_FUNC_IMPL(func_")):
            return i
    return len(text.splitlines())


GRUPO_RE = re.compile(r"GRUPO:(\S+)")


def verify(chunks, manifest: Path) -> int:
    """Conta cada marcador do manifesto em todo o lift alvo. rc=1 se faltar.

    Suporta uma 5a coluna opcional (`nota`), aditiva e retro-compativel --
    marcadores sem ela seguem exactamente o comportamento pre-existente:
      - `OBSOLETO: <razao>`  -- o marcador nunca falha o gate (Repudiation
        T-03-08); e' impresso numa categoria informativa separada, nunca
        em AUSENTE/A MENOS.
      - `GRUPO:<id>`         -- marcadores com o mesmo id sao verificados
        pela SOMA de found/min_count do grupo, nao individualmente
        (D-3.1c: conversoes que trocam substituicao 1-para-1 entre dois
        marcadores nao devem punir o par quando a soma se mantem).
    """
    wanted: list[tuple[str, str, int, str, str]] = []
    for line in manifest.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split("\t")
        marker, kind, n, chunks_s = parts[:4]
        nota = parts[4] if len(parts) > 4 else ""
        wanted.append((marker, kind, int(n), chunks_s, nota))

    found = {marker: 0 for marker, _, _, _, _ in wanted}
    for path in chunks:
        text = path.read_text(errors="replace")
        for marker in found:
            found[marker] += text.count(marker)

    obsolete_entries = [w for w in wanted if w[4].startswith("OBSOLETO")]
    grouped_entries = [w for w in wanted if GRUPO_RE.match(w[4])]
    obsolete_or_grouped = {w[0] for w in obsolete_entries} | {w[0] for w in grouped_entries}
    normal_entries = [w for w in wanted if w[0] not in obsolete_or_grouped]

    missing = [(m, k, n, found[m]) for m, k, n, _, _ in normal_entries if found[m] == 0]
    short = [(m, k, n, found[m]) for m, k, n, _, _ in normal_entries if 0 < found[m] < n]

    for marker, kind, want, got in missing:
        print(f"AUSENTE  {kind:6} {marker}  (esperado >={want}, encontrado 0)")
    for marker, kind, want, got in short:
        print(f"A MENOS  {kind:6} {marker}  (esperado >={want}, encontrado {got})")

    # OBSOLETO (T-03-08 mitigado): nunca falha o gate, seja found==0 ou >0.
    for marker, kind, want, chunks_s, nota in obsolete_entries:
        razao = nota[len("OBSOLETO"):].lstrip(":").strip()
        print(f"OBSOLETO  {kind}  {marker} -- {razao}")

    # GRUPO (D-3.1c): soma de found/min_count decide, nao cada marcador isolado.
    groups: dict[str, list[tuple[str, str, int, int]]] = defaultdict(list)
    for marker, kind, want, chunks_s, nota in grouped_entries:
        gid = GRUPO_RE.match(nota).group(1)
        groups[gid].append((marker, kind, want, found[marker]))

    group_failed = 0
    group_passed = 0
    for gid, items in sorted(groups.items()):
        sum_want = sum(want for _, _, want, _ in items)
        sum_found = sum(got for _, _, _, got in items)
        if sum_found < sum_want:
            group_failed += 1
            names = "+".join(m for m, _, _, _ in items)
            print(
                f"A MENOS (grupo)  {gid}: {names} "
                f"esperado>={sum_want} encontrado={sum_found}"
            )
        else:
            group_passed += 1

    total = len(wanted)
    ok = total - len(missing) - len(short) - len(obsolete_entries) - len(grouped_entries)
    print(f"\nbaseline: {ok}/{total} marcadores intactos, "
          f"{len(missing)} ausentes, {len(short)} a menos")
    print(
        f"obsoletos: {len(obsolete_entries)} citados (nunca falham o gate) | "
        f"grupos: {group_passed} passaram, {group_failed} falharam "
        f"(de {len(groups)} grupos, {len(grouped_entries)} marcadores)"
    )
    return 1 if (missing or short or group_failed) else 0


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    lift = Path(sys.argv[1])
    chunks = sorted(lift.glob("ppu_recomp_*.cpp"))
    if not chunks:
        print(f"sem chunks em {lift}", file=sys.stderr)
        return 2

    if "--verify" in sys.argv:
        return verify(chunks, Path(sys.argv[sys.argv.index("--verify") + 1]))

    pure_lines = set(PURE.read_text(errors="replace").splitlines())
    pure_text = PURE.read_text(errors="replace")
    # simbolos e globais que o proprio lifter emite -- nao sao injeccao nossa
    lifter_syms = set(SYM_RE.findall(pure_text)) | set(GLOBAL_RE.findall(pure_text))
    # D-2.1 (02-CONTEXT.md, Fase 2): dos 3 identificadores do preambulo puro,
    # so' 2 ganham marcador kind=PREAMBLE. ps3_timebase_now fica EXCLUIDO --
    # foi superseded pelo contrato ppu_timebase_now (Fase 1, commit e441f37,
    # runtime/syscalls/sys_timer.c:80-101). So' sobrevive hoje numa probe do
    # chunk 000 de uma arvore de safra mista; gatea-lo produziria alarme
    # falso num re-lift limpo, nao uma regressao real.
    preamble_syms = lifter_syms - {"ps3_timebase_now"}

    counts: dict[tuple[str, str], int] = defaultdict(int)
    origin: dict[tuple[str, str], set[str]] = defaultdict(set)

    for path in chunks:
        name = path.name
        text = path.read_text(errors="replace")
        lines = text.splitlines()
        end = preamble_end(text)
        injected = [ln for ln in lines[:end] if ln not in pure_lines]

        # TAGs: procuradas no ficheiro INTEIRO (os call sites vivem nos corpos)
        for tag in TAG_RE.findall(text):
            counts[("TAG", tag)] += 1
            origin[("TAG", tag)].add(name)

        # SYM/GLOBAL: so' o que e' DEFINIDO no preambulo injectado
        blob = "\n".join(injected)
        for sym in set(SYM_RE.findall(blob)) - lifter_syms:
            counts[("SYM", sym)] += text.count(sym)
            origin[("SYM", sym)].add(name)
        for gvar in set(GLOBAL_RE.findall(blob)) - lifter_syms:
            counts[("GLOBAL", gvar)] += text.count(gvar)
            origin[("GLOBAL", gvar)].add(name)

        # PREAMBLE: confirma que o preambulo puro (nao-injectado) SOBREVIVE
        # no chunk alvo. Diferente do bloco SYM/GLOBAL acima -- conta contra
        # o `text` do ficheiro INTEIRO, nao contra `blob`/`injected`, porque
        # o objectivo aqui nao e' detectar injeccao, e' confirmar sobrevivencia.
        for sym in preamble_syms:
            if sym in text:
                counts[("PREAMBLE", sym)] += text.count(sym)
                origin[("PREAMBLE", sym)].add(name)

    print("# MANIFEST do baseline forense do lift -- RDY-0 Task 1")
    print(f"# gerado por gen_manifest.py a partir de {lift.name}")
    print("# marcador\ttipo\tmin_count\tchunks_origem")
    for (kind, marker), n in sorted(counts.items(), key=lambda kv: (kv[0][0], kv[0][1])):
        chunks_s = ",".join(sorted(origin[(kind, marker)]))
        print(f"{marker}\t{kind}\t{n}\t{chunks_s}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
