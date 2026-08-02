#!/usr/bin/env python3
"""Gera o PATCH_MIGRATION.tsv -- ledger de migracao patch->mecanismo.

Fase 16, Plano 16-01, Task 2 (requisito LEDG-01).

Irmao de `gen_catalog.py`, nao extensao dele: o catalogo e' 100% derivado e
"NUNCA editado a mao"; o ledger tem 4 colunas que SAO editadas por humano
(`alvo`, `prioridade`, `aceite`, `estado`). Misturar os dois no mesmo gerador
apagaria a fronteira derivado/editado que a 16-CONTEXT.md fixou -- e' essa
fronteira que impede o ledger de apodrecer no primeiro regen.

Universo: os `patch_*.py` de `../gow2-recomp/recomp_mid_v2` (o corpus que o
`build_macos.sh`/`apply_all_patches.sh` de facto aplicam). O espelho subtree
`games/gow2/recomp_mid_v2` esta' atrasado e serve APENAS para a coluna
`so_no_build` e para a nota de divergencia no cabecalho; os patches que so'
existem nele NAO ganham linha (nao fazem parte do que o build corre).
Reconciliar o subtree e' divida declarada, fora do escopo desta fase.

Colunas obrigatorias (LEDG-01 / ROADMAP):
  patch, classe, alvo, ea, prioridade, aceite, estado
Colunas auxiliares derivadas:
  subclasse_catalogo, so_no_build, marcador

Derivacao da coluna `classe` (mapa de 16-RESEARCH.md; NUNCA copiada a mao --
sai de um join com PATCH_CATALOG.tsv pelo nome do ficheiro):

  PATCH_CATALOG.classe | PATCH_CATALOG.subclasse | PATCH_MIGRATION.classe
  ---------------------+-------------------------+-----------------------
  PROBE                | orfao-sem-fonte         | OBSOLETE
  PROBE                | qualquer outra          | PROBE
  FUNCIONAL            | opd                     | OPD
  FUNCIONAL            | qualquer outra          | CORRECTNESS

`BUILD` pertence ao dominio de LEDG-01 mas hoje nao e' produzido: nenhum
patch do corpus mexe so' em build/scripts. Fica reservado, nao forcado.

Heuristica da coluna `ea` (declarada como heuristica no cabecalho do TSV --
nao e' uma medicao, e' um palpite verificavel pelo humano na 16-02), na
ordem, o primeiro que casar decide:

  1. `func_XXXXXXXX` no NOME do ficheiro
  2. `0xXXXXXXXX` no NOME do ficheiro
  3. token hexadecimal no NOME (ex.: `2550c8` em patch_fallthrough_2550c8.py)
     CUJO `func_<pad8>` aparece de facto no CORPO -- a correlacao nome<->corpo
     e' o que impede um token como `d3d12` de virar uma EA inventada
  4. primeiro `void func_XXXXXXXX` no CORPO (a assinatura que o patch ancora)
  5. `func_XXXXXXXX` numa linha `SIG =` / `FUNC_SIG` do CORPO
  6. `-` (nenhuma EA identificavel -- e' informacao, nao falha: um patch sem
     EA nao e' migravel para midasm/weak e por isso nao pode ser P0)

`--merge <ledger>` preserva as 4 colunas humanas das linhas cujo patch ainda
existe; as colunas derivadas sao sempre recalculadas (um regen depois de um
re-lift tem de reflectir o catalogo novo, nao o congelado).

Uso:
  .venv/bin/python3 games/gow2/lift_baseline/gen_migration_ledger.py \\
    [--catalog games/gow2/lift_baseline/PATCH_CATALOG.tsv] \\
    [--build-dir ../gow2-recomp/recomp_mid_v2] \\
    [--mono-dir games/gow2/recomp_mid_v2] \\
    [--merge games/gow2/lift_baseline/PATCH_MIGRATION.tsv] \\
    [-o games/gow2/lift_baseline/PATCH_MIGRATION.tsv]

Sem `-o` escreve em stdout. Paths relativos resolvem contra a raiz do
monorepo (deduzida da localizacao deste ficheiro), nao contra o cwd.
"""
from __future__ import annotations

import argparse
import datetime
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MONOREPO_ROOT = HERE.parents[2]

COLUMNS = (
    "patch",
    "classe",
    "alvo",
    "ea",
    "prioridade",
    "aceite",
    "estado",
    "ea_pista_nome",
    "subclasse_catalogo",
    "so_no_build",
    "marcador",
)

# As unicas colunas que um humano edita (16-CONTEXT.md). `--merge` preserva
# estas e so' estas.
HUMAN_COLUMNS = ("alvo", "prioridade", "aceite", "estado")

CLASSES_LEDGER = ("CORRECTNESS", "PROBE", "OPD", "BUILD", "OBSOLETE")

# Colunas do PATCH_CATALOG.tsv (a linha de cabecalho la' e' comentada, por
# isso lemos os nomes do proprio ficheiro quando possivel e caimos aqui).
CATALOG_COLUMNS_FALLBACK = (
    "patch",
    "escreve",
    "classe",
    "subclasse",
    "no_gate",
    "razao",
    "marcador",
    "chunk_alvo",
)

_RE_NAME_FUNC = re.compile(r"func_([0-9A-Fa-f]{8})")
_RE_NAME_HEX0X = re.compile(r"0x([0-9A-Fa-f]{8})")
_RE_NAME_TOKEN = re.compile(r"[0-9A-Fa-f]{4,8}")
_RE_BODY_VOID = re.compile(r"void\s+func_([0-9A-Fa-f]{8})")
_RE_BODY_SIG = re.compile(r"(?:FUNC_SIG|SIG\s*=)[^\n]*func_([0-9A-Fa-f]{8})")


# ---------------------------------------------------------------------------
# Derivacao
# ---------------------------------------------------------------------------


def map_classe(classe_catalogo: str, subclasse_catalogo: str) -> str:
    """Mapa catalogo -> ledger (ver docstring do modulo). Funcao pura."""
    if classe_catalogo == "PROBE":
        if subclasse_catalogo == "orfao-sem-fonte":
            return "OBSOLETE"
        return "PROBE"
    if classe_catalogo == "FUNCIONAL":
        if subclasse_catalogo == "opd":
            return "OPD"
        return "CORRECTNESS"
    raise ValueError(
        f"classe de catalogo desconhecida: {classe_catalogo!r}/"
        f"{subclasse_catalogo!r} -- o mapa tem de ser actualizado "
        "explicitamente, nunca cair num default silencioso"
    )


def default_alvo(classe_ledger: str) -> str:
    """Alvo por omissao. Vazio = decisao humana pendente (16-02)."""
    if classe_ledger == "PROBE":
        return "keep-probe"
    if classe_ledger == "OBSOLETE":
        # Proposta, nao execucao: ninguem apaga nada nesta fase.
        return "delete"
    return ""


def normalize_ea(hexstr: str) -> str:
    """`2550c8` / `002550C8` -> `0x002550C8`."""
    return "0x" + hexstr.upper().rjust(8, "0")


def detect_ea(name: str, src: str) -> str:
    """Heuristica de EA (6 ramos, ver docstring do modulo). Funcao pura."""
    m = _RE_NAME_FUNC.search(name)
    if m:
        return normalize_ea(m.group(1))

    m = _RE_NAME_HEX0X.search(name)
    if m:
        return normalize_ea(m.group(1))

    # Ramo 3: token hex do nome CORRELACIONADO com o corpo.
    stem = name[: -len(".py")] if name.endswith(".py") else name
    for token in _RE_NAME_TOKEN.findall(stem):
        if not any(c.isdigit() for c in token):
            continue
        pad = token.upper().rjust(8, "0")
        # src.upper() dos dois lados: o corpo escreve `func_002550C8` mas o
        # token do nome vem em minusculas (`2550c8`).
        if f"FUNC_{pad}" in src.upper():
            return "0x" + pad

    m = _RE_BODY_VOID.search(src)
    if m:
        return normalize_ea(m.group(1))

    m = _RE_BODY_SIG.search(src)
    if m:
        return normalize_ea(m.group(1))

    return "-"


def ea_pista_do_nome(name: str) -> str:
    """Candidato a EA lido SO' do nome do ficheiro, NAO confirmado pelo corpo.

    A convencao `patch_<hex>_<descricao>.py` sugere um endereco em quase todo
    o corpus, mas em dezenas de scripts o corpo nunca menciona essa funcao (o
    patch ancora numa fatia de codigo, num vizinho, ou o nome refere o SITIO e
    nao a funcao). Escrever esse numero na coluna `ea` seria forjar uma
    medicao; fica aqui, declarado como pista a verificar na 16-02.
    Devolve "" quando o nome nao tem nenhum token hexadecimal plausivel.
    """
    stem = name[: -len(".py")] if name.endswith(".py") else name
    for token in _RE_NAME_TOKEN.findall(stem):
        if not any(c.isdigit() for c in token):
            continue
        return "0x" + token.upper().rjust(8, "0")
    return ""


# ---------------------------------------------------------------------------
# IO
# ---------------------------------------------------------------------------


def _catalog_columns(text: str) -> tuple[str, ...]:
    """Nomes de coluna lidos da linha `# patch\\tescreve\\t...` do catalogo."""
    for line in text.splitlines():
        if line.startswith("#") and "\t" in line:
            cols = tuple(c.strip() for c in line.lstrip("#").strip().split("\t"))
            if cols and cols[0] == "patch":
                return cols
    return CATALOG_COLUMNS_FALLBACK


def load_catalog(path: Path) -> dict[str, dict]:
    """Le o PATCH_CATALOG.tsv -> {nome do patch: linha}. Read-only."""
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    cols = _catalog_columns(text)
    out: dict[str, dict] = {}
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        campos = line.split("\t")
        # Preenche a direita: o TSV pode ter campos finais vazios aparados.
        campos += [""] * (len(cols) - len(campos))
        linha = dict(zip(cols, campos))
        out[linha["patch"]] = linha
    return out


def parse_ledger(text: str) -> dict[str, dict]:
    """Le um PATCH_MIGRATION.tsv (texto) -> {nome do patch: linha}."""
    cols: tuple[str, ...] | None = None
    out: dict[str, dict] = {}
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        campos = line.split("\t")
        if cols is None:
            if campos[0] == "patch":
                cols = tuple(campos)
                continue
            cols = COLUMNS
        campos += [""] * (len(cols) - len(campos))
        linha = dict(zip(cols, campos))
        out[linha["patch"]] = linha
    return out


# ---------------------------------------------------------------------------
# Construcao das linhas
# ---------------------------------------------------------------------------


def build_rows(
    catalog: dict[str, dict],
    build_dir: Path,
    mono_dir: Path,
    anterior: dict[str, dict] | None = None,
) -> list[dict]:
    """Uma linha por `patch_*.py` de `build_dir`, ordenada por nome.

    `anterior` (o ledger de uma corrida passada) so' repoe HUMAN_COLUMNS; as
    colunas derivadas sao sempre recalculadas a partir do catalogo e do disco.
    Falha ruidosamente se um patch do corpus nao estiver no catalogo -- isso
    significa catalogo desactualizado, e um silencio aqui reintroduzia
    exactamente o buraco de 50 patches que a Task 1 fechou.
    """
    anterior = anterior or {}
    mono_nomes = {p.name for p in Path(mono_dir).glob("patch_*.py")}
    rows: list[dict] = []
    em_falta: list[str] = []

    for path in sorted(Path(build_dir).glob("patch_*.py")):
        nome = path.name
        linha_cat = catalog.get(nome)
        if linha_cat is None:
            em_falta.append(nome)
            continue
        src = path.read_text(encoding="utf-8", errors="replace")
        classe = map_classe(linha_cat["classe"], linha_cat["subclasse"])
        ea = detect_ea(nome, src)
        row = {
            "patch": nome,
            "classe": classe,
            "alvo": default_alvo(classe),
            "ea": ea,
            "ea_pista_nome": ea_pista_do_nome(nome) if ea == "-" else "",
            "prioridade": "",
            "aceite": "",
            "estado": "todo",
            "subclasse_catalogo": linha_cat["subclasse"],
            "so_no_build": "0" if nome in mono_nomes else "1",
            "marcador": linha_cat.get("marcador", ""),
        }
        prev = anterior.get(nome)
        if prev:
            for col in HUMAN_COLUMNS:
                valor = prev.get(col, "")
                if valor != "":
                    row[col] = valor
        rows.append(row)

    if em_falta:
        raise SystemExit(
            f"{len(em_falta)} patch(es) do corpus de build ausentes do catalogo: "
            f"{', '.join(em_falta[:5])}{'...' if len(em_falta) > 5 else ''}\n"
            "Regenerar primeiro: gen_catalog.py ../gow2-recomp/recomp_mid_v2 "
            "games/gow2/lift_baseline/MANIFEST.tsv > "
            "games/gow2/lift_baseline/PATCH_CATALOG.tsv"
        )
    return rows


def medir_contagens(
    catalog: dict[str, dict], build_dir: Path, mono_dir: Path
) -> dict[str, object]:
    """Contagens MEDIDAS no disco nesta corrida (nunca copiadas de um plano)."""
    build_nomes = {p.name for p in Path(build_dir).glob("patch_*.py")}
    mono_nomes = {p.name for p in Path(mono_dir).glob("patch_*.py")}
    return {
        "n_build": len(build_nomes),
        "n_mono": len(mono_nomes),
        "n_cat": len(catalog),
        "build_dir": str(build_dir),
        "mono_dir": str(mono_dir),
        "so_no_mono": sorted(mono_nomes - build_nomes),
    }


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------


def render_tsv(rows: list[dict], contagens: dict, data: str | None = None) -> str:
    data = data or datetime.date.today().isoformat()
    n_build = int(contagens["n_build"])
    n_mono = int(contagens["n_mono"])
    n_cat = int(contagens["n_cat"])
    so_no_mono = list(contagens.get("so_no_mono") or [])

    por_classe: dict[str, int] = {}
    for r in rows:
        por_classe[r["classe"]] = por_classe.get(r["classe"], 0) + 1
    resumo = " / ".join(
        f"{c}={por_classe[c]}" for c in CLASSES_LEDGER if c in por_classe
    )
    com_ea = sum(1 for r in rows if r["ea"] != "-")
    com_pista = sum(1 for r in rows if r.get("ea_pista_nome"))

    header = [
        "# PATCH_MIGRATION.tsv -- ledger de migracao patch->mecanismo (Fase 16 / LEDG-01)",
        "# regenerar esqueleto: .venv/bin/python3 games/gow2/lift_baseline/gen_migration_ledger.py"
        " --merge games/gow2/lift_baseline/PATCH_MIGRATION.tsv"
        " -o games/gow2/lift_baseline/PATCH_MIGRATION.tsv",
        "# COLUNAS HUMANAS (nao sobrescrever no regen se --merge): alvo, prioridade, aceite, estado",
        "# COLUNAS DERIVADAS (recalculadas sempre): patch, classe, ea (heuristica,"
        " so' quando CONFIRMADA pelo corpo do script), ea_pista_nome (candidato lido"
        " do nome e NAO confirmado -- verificar antes de usar), subclasse_catalogo,"
        " so_no_build, marcador",
        f"# baseline contagens ({data}, medidas nesta corrida):",
        f"#   patch_*.py monorepo ({contagens['mono_dir']}) = {n_mono}",
        f"#   patch_*.py build    ({contagens['build_dir']}) = {n_build}",
        f"#   PATCH_CATALOG linhas de dados = {n_cat}",
        f"#   linhas de dados deste ledger = {len(rows)} ({resumo})",
        f"#   EA CONFIRMADA pelo corpo do script = {com_ea}/{len(rows)}; destas"
        f" restantes, {com_pista} trazem pista nao confirmada em ea_pista_nome"
        " (sem EA verificada nao ha' midasm/weak, logo nao ha' P0)",
        f"#   divergencia build-monorepo = {n_build} - {n_mono} = {n_build - n_mono}"
        " (declarada; reconciliar o subtree e' divida do v1.0, FORA de escopo)",
    ]
    if so_no_mono:
        header.append(
            f"#   {len(so_no_mono)} patch(es) existem SO' no espelho monorepo e NAO tem"
            f" linha (o build nao os aplica): {', '.join(so_no_mono)}"
        )
    header += [
        "# baseline verify/smoke: POR MEDIR (plano 16-03) -- rc=? st620_max=? sticky=?"
        " oob_pos_tls=? [nivel de evidencia: nao-exercitado]",
        "# dominio: classe in {CORRECTNESS,PROBE,OPD,BUILD,OBSOLETE} (BUILD reservado,"
        " hoje sem ocorrencias) | alvo in {midasm,weak,switch_table,invalid_insn,runtime,"
        "keep-probe,delete} | prioridade in {P0,P1,P2} | estado in {todo,migrated,wont}",
        "# mapa classe (derivado, ver 16-RESEARCH.md e o docstring de gen_migration_ledger.py):",
        "#   PROBE+orfao-sem-fonte->OBSOLETE | PROBE->PROBE | FUNCIONAL+opd->OPD |"
        " FUNCIONAL->CORRECTNESS",
        "# alvo/prioridade/aceite vazios = decisao humana pendente (plano 16-02).",
        "# aceite tem de ser executavel: grep:<padrao> | contract:<id CONTRACTS.tsv> |"
        " smoke:<metrica>. 'verificar manualmente' e' proibido.",
    ]

    lines = list(header)
    lines.append("\t".join(COLUMNS))
    for row in rows:
        lines.append("\t".join(row[col] for col in COLUMNS))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _resolve(p: str) -> Path:
    path = Path(p)
    return path if path.is_absolute() else (MONOREPO_ROOT / path)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Gera o PATCH_MIGRATION.tsv (ledger de migracao, LEDG-01)."
    )
    ap.add_argument("--catalog", default="games/gow2/lift_baseline/PATCH_CATALOG.tsv")
    ap.add_argument("--build-dir", default="../gow2-recomp/recomp_mid_v2")
    ap.add_argument("--mono-dir", default="games/gow2/recomp_mid_v2")
    ap.add_argument(
        "--merge",
        default=None,
        help="ledger anterior cujas colunas humanas devem ser preservadas",
    )
    ap.add_argument("-o", "--output", default=None, help="destino (default: stdout)")
    args = ap.parse_args(argv)

    catalog_path = _resolve(args.catalog)
    build_dir = _resolve(args.build_dir)
    mono_dir = _resolve(args.mono_dir)

    if not catalog_path.is_file():
        print(f"catalogo nao encontrado: {catalog_path}", file=sys.stderr)
        return 2
    if not build_dir.is_dir():
        print(f"nao e' um directorio: {build_dir}", file=sys.stderr)
        return 2
    if not mono_dir.is_dir():
        print(f"nao e' um directorio: {mono_dir}", file=sys.stderr)
        return 2

    anterior: dict[str, dict] = {}
    if args.merge:
        merge_path = _resolve(args.merge)
        if merge_path.is_file():
            anterior = parse_ledger(
                merge_path.read_text(encoding="utf-8", errors="replace")
            )
        else:
            print(
                f"[aviso] --merge {merge_path} nao existe; a gerar de raiz",
                file=sys.stderr,
            )

    catalog = load_catalog(catalog_path)
    rows = build_rows(catalog, build_dir, mono_dir, anterior=anterior)
    contagens = medir_contagens(catalog, build_dir, mono_dir)
    # No cabecalho ficam os paths COMO FORAM PEDIDOS (relativos a' raiz do
    # monorepo), nao os absolutos da maquina de quem correu: o TSV e'
    # versionado e um /Users/<alguem>/ la' dentro e' ruido e ma' reproducao.
    contagens["build_dir"] = args.build_dir
    contagens["mono_dir"] = args.mono_dir
    texto = render_tsv(rows, contagens)

    if args.output:
        _resolve(args.output).write_text(texto, encoding="utf-8")
    else:
        sys.stdout.write(texto)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
