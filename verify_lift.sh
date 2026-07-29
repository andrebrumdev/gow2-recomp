#!/usr/bin/env bash
# verify_lift.sh -- ponto de entrada UNICO para os 3 verificadores do lift.
#
# Corre, contra um LIFT_DIR dado:
#   1. tools/lift_parity.py     (--functions, autoridade das fronteiras)
#   2. games/gow2/verify_lift_baseline.sh  (MANIFEST.tsv, script INALTERADO)
#   3. tools/audit_boundaries.py (I1/I3; I2 e' informativo, fora do gate)
#
# Os 3 passos falham por DELTA contra um baseline CONGELADO
# (lift_baseline/PARITY_BASELINE.json, MANIFEST_DEBT_BASELINE.json,
# BOUNDS_BASELINE.json), nunca por limiar absoluto -- ja provado na Fase 4
# que um limiar absoluto pune melhorias (D-4.5, 04-CONTEXT.md), e estendido
# ao passo 2 na Fase 5 (D-5.1, 05-CONTEXT.md): o passo 2 continua a imprimir
# o detalhe por-marcador de verify_lift_baseline.sh (transparencia humana),
# mas o rc autoritativo vem de lift_baseline/manifest_delta_gate.py --
# so' falha por achado NOVO face a divida ja' declarada (grupo opd-dispatch,
# Fase 3), nao pelo rc absoluto de gen_manifest.py --verify.
#
# O oraculo (I4/I5, item 3 do plano de adopcao) fica FORA -- corre-se
# audit_boundaries.py SEM --oracle.
#
# Uso:  ./verify_lift.sh LIFT_DIR
# rc=0  os 3 passos passam (delta limpo nos 3 -- lift_parity, MANIFEST, audit_boundaries)
# rc=1  pelo menos um passo falhou
# rc=2  erro de uso (LIFT_DIR ausente, ELF/functions.json/baseline em falta)
#
# Overrides:
#   PS3_ELF          caminho do EBOOT.ELF (default: $LIFT_DIR/../EBOOT.ELF)
#   PS3_FUNCTIONS    caminho do functions.json (default: $LIFT_DIR/../functions.json)
#   PS3_ENGINE_ROOT  raiz do motor (default: dois niveis acima deste script)
#   PS3_PATCH_PYTHON interpretador python (default: .venv/bin/python3 do motor)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PS3_ROOT="${PS3_ENGINE_ROOT:-$(cd "$HERE/../.." && pwd)}"
BASE="$HERE/lift_baseline"

if [ $# -lt 1 ]; then
    echo "uso: $0 LIFT_DIR" >&2
    exit 2
fi
LIFT="$(cd "$1" 2>/dev/null && pwd)"
if [ -z "$LIFT" ]; then
    echo "ERRO: dir de lift inexistente: $1" >&2
    exit 2
fi
GOW2_ROOT="$(dirname "$LIFT")"
ELF="${PS3_ELF:-$GOW2_ROOT/EBOOT.ELF}"
FUNCTIONS="${PS3_FUNCTIONS:-$GOW2_ROOT/functions.json}"

[ -f "$ELF" ] || { echo "ERRO: ELF em falta: $ELF (defina PS3_ELF)" >&2; exit 2; }
[ -f "$FUNCTIONS" ] || { echo "ERRO: functions.json em falta: $FUNCTIONS (defina PS3_FUNCTIONS)" >&2; exit 2; }
[ -f "$BASE/PARITY_BASELINE.json" ] || { echo "ERRO: baseline em falta: $BASE/PARITY_BASELINE.json" >&2; exit 2; }
[ -f "$BASE/BOUNDS_BASELINE.json" ] || { echo "ERRO: baseline em falta: $BASE/BOUNDS_BASELINE.json" >&2; exit 2; }

PY="${PS3_PATCH_PYTHON:-}"
if [ -z "$PY" ]; then
    if [ -x "$PS3_ROOT/.venv/bin/python3" ]; then PY="$PS3_ROOT/.venv/bin/python3"
    else PY="$(command -v python3 || true)"; fi
fi
[ -n "$PY" ] || { echo "ERRO: sem interpretador python3" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v shasum >/dev/null 2>&1; then
    SHA="$(cat "$LIFT"/ppu_recomp_*.cpp 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"
else
    SHA="$(cat "$LIFT"/ppu_recomp_*.cpp 2>/dev/null | sha256sum | cut -d' ' -f1)"
fi

echo "== verify_lift.sh =="
echo "LIFT:      $LIFT"
echo "SHA256:    ${SHA:-<sem chunks ppu_recomp_*.cpp>}"
echo "ELF:       $ELF"
echo "FUNCTIONS: $FUNCTIONS"
echo

NAMES=()
RESULTS=()

run_step() {
    local nome="$1" fn="$2"
    echo "---- [$nome] ----"
    if "$fn"; then
        echo "[$nome] PASS"
        NAMES+=("$nome"); RESULTS+=(0)
    else
        local rc=$?
        echo "[$nome] FAIL (rc=$rc)"
        NAMES+=("$nome"); RESULTS+=(1)
    fi
    echo
}

parity_step() {
    "$PY" "$PS3_ROOT/tools/lift_parity.py" "$ELF" "$LIFT" \
        --functions "$FUNCTIONS" --limit 0 --json "$TMP/parity_current.json" || return 1
    "$PY" - "$TMP/parity_current.json" "$TMP/parity_current.ids.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
ids = sorted(f"{x['ea']}/{x['signal']}" for x in d["findings"])
with open(sys.argv[2], "w") as f:
    json.dump({"ids": ids}, f)
PYEOF
    "$PY" "$BASE/baseline_delta.py" "$TMP/parity_current.ids.json" "$BASE/PARITY_BASELINE.json" \
        --label lift_parity
}

manifest_step() {
    # Detalhe por-marcador (transparencia humana) -- o rc deste sub-passo ja
    # NAO e' autoritativo: um deficit ja' declarado (ex.: grupo opd-dispatch,
    # Fase 3) faz verify_lift_baseline.sh sair rc=1 mesmo sem regressao nova.
    PS3_ENGINE_ROOT="$PS3_ROOT" "$HERE/verify_lift_baseline.sh" "$LIFT"
    # Interpretacao por DELTA contra a divida congelada (D-5.1): so' falha
    # por achado NOVO face a MANIFEST_DEBT_BASELINE.json, nunca por limiar
    # absoluto -- fecha o gap deixado em aberto por 04-03-SUMMARY.md.
    "$PY" "$BASE/manifest_delta_gate.py" "$LIFT" --manifest "$BASE/MANIFEST.tsv" \
        --debt "$BASE/MANIFEST_DEBT_BASELINE.json"
    local rc=$?
    return $rc
}

bounds_step() {
    "$PY" "$PS3_ROOT/tools/audit_boundaries.py" "$FUNCTIONS" --elf "$ELF" \
        --json "$TMP/bounds_current.json" --max-report 3 || return 1
    "$PY" - "$TMP/bounds_current.json" "$TMP/bounds_current.ids.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
ids = sorted([f"I1:{x['a']}|{x['b']}" for x in d["I1"]] + [f"I3:{x['func']}" for x in d["I3"]])
with open(sys.argv[2], "w") as f:
    json.dump({"ids": ids}, f)
PYEOF
    "$PY" "$BASE/baseline_delta.py" "$TMP/bounds_current.ids.json" "$BASE/BOUNDS_BASELINE.json" \
        --label audit_boundaries
}

run_step "lift_parity" parity_step
run_step "MANIFEST" manifest_step
run_step "audit_boundaries" bounds_step

echo "== rodape =="
overall=0
for i in "${!NAMES[@]}"; do
    if [ "${RESULTS[$i]}" = "0" ]; then
        printf '%-20s PASS\n' "${NAMES[$i]}"
    else
        printf '%-20s FAIL\n' "${NAMES[$i]}"
        overall=1
    fi
done

exit $overall
