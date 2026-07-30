#!/usr/bin/env bash
# smoke_chain_gate.sh -- GATE-01/GATE-02 (Fase 7, marco v1.1): mede a cadeia
# completa do boot (intro -> 2o movie -> re-Play -> AUTO_LOAD -> WAD) --
# nao so' o st620 (o buraco medido em 07-CONTEXT.md: o smoke do v1.0 passa
# com st620=11 num binario que nao desenha um unico frame depois da intro).
#
# Uso (Task 1 -- uma so corrida contra um binario ja construido):
#   ./smoke_chain_gate.sh --bin BIN_PATH [LOG] [TIMEOUT]
#
# (o modo LIFT_REL/N-corridas e o loop de multiplas execucoes ficam para a
# Task 2 deste mesmo plano -- 07-01-PLAN.md)
#
# rc: 0 se a cadeia chega ao fim (elo_stopped=nenhum, os 5 elos bloqueantes
# passam); 1 senao, com o elo que falhou nomeado explicitamente na coluna
# elo_stopped -- nunca so um rc mudo (T-07-01-02).
#
# Kill SEMPRE por PID (TERM depois -9, via measure_one() em
# lib_boot_chain_metrics.sh). NUNCA pkill -f boot_gow2.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE" || exit 1

[ -f EBOOT.ELF ] || { echo "ERRO: falta EBOOT.ELF em $HERE" >&2; exit 2; }
[ -f env_gow2.sh ] || { echo "ERRO: falta env_gow2.sh em $HERE" >&2; exit 2; }

# Nucleo partilhado com bisect_regression.sh (Fase 6) -- nenhum grep da
# cadeia escrito duas vezes.
# shellcheck source=lib_boot_chain_metrics.sh
source "$HERE/lib_boot_chain_metrics.sh"

if [ "${1:-}" != "--bin" ]; then
  echo "ERRO: uso (Task 1): smoke_chain_gate.sh --bin BIN_PATH [LOG] [TIMEOUT]" >&2
  exit 2
fi
BIN_PATH="${2:-}"
if [ -z "$BIN_PATH" ]; then
  echo "ERRO: --bin precisa de um caminho de binario" >&2
  exit 2
fi
# bash so' procura em PATH quando o nome nao tem "/" -- resolver para
# caminho absoluto para nunca depender do PATH do operador.
case "$BIN_PATH" in
  */*) : ;;
  *) BIN_PATH="$HERE/$BIN_PATH" ;;
esac
if [ ! -x "$BIN_PATH" ]; then
  echo "ERRO: binario inexistente ou nao executavel: $BIN_PATH" >&2
  exit 2
fi
LOG_PATH="${3:-/tmp/chain_gate_$(basename "$BIN_PATH")_$(date +%Y%m%d_%H%M%S).log}"
TIMEOUT="${4:-90}"

set -a; . "$HERE/env_gow2.sh"; set +a
arm_menu_fast_recipe

measure_one "$BIN_PATH" "$LOG_PATH" "$TIMEOUT"

read -r LOG_LINES STARTSEQ THR_END R_PERMA NOPIC <<< "$(extract_counts "$LOG_PATH")"
ST620="$(extract_st620 "$LOG_PATH")"

# ---- SetFlip_after_R_Perm / Pad_total (elos 6/7, informativos nesta task) --
# Reutiliza count_gate() de count_menu_gate.py via um one-liner -- nunca
# reimplementar estes dois greps aqui.
SETFLIP_AFTER=0
PAD_TOTAL=0
read -r SETFLIP_AFTER PAD_TOTAL <<< "$(python3 - "$HERE" "$LOG_PATH" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from count_menu_gate import count_gate
d = count_gate(sys.argv[2])
print(d["SetFlip_after_R_Perm"], d["Pad_total"])
PY
)"
SETFLIP_AFTER=${SETFLIP_AFTER:-0}
PAD_TOTAL=${PAD_TOTAL:-0}

# ---- deriva elo_stopped andando pela cadeia por ORDEM, parando no PRIMEIRO
# elo cujo valor nao bate o "bom". Os elos 6/7 (SetFlip_after_R_Perm/
# Pad_total) sao sempre impressos mas NAO decidem elo_stopped nem o rc
# nesta task (ver 07-CONTEXT.md / Task 3 para a medicao real deles).
ELO_STOPPED="nenhum"
if [ "${ST620:-0}" -lt 3 ] 2>/dev/null; then
  ELO_STOPPED="intro (st620)"
elif [ "${STARTSEQ:-0}" -lt 2 ] 2>/dev/null; then
  ELO_STOPPED="2o movie (StartSeq)"
elif [ "${NOPIC:-0}" -lt 4 ] 2>/dev/null; then
  ELO_STOPPED="re-Play (NOPIC)"
elif [ "${THR_END:-0}" -lt 1 ] 2>/dev/null; then
  ELO_STOPPED="AUTO_LOAD (thr_end)"
elif [ "${R_PERMA:-0}" -lt 1 ] 2>/dev/null; then
  ELO_STOPPED="WAD (R_PermA)"
fi

printf 'bin\tst620\tstartseq\tnopic\tthr_end\tr_perma\tsetflip_after_rperm\tpad_total\telo_stopped\n'
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(basename "$BIN_PATH")" "$ST620" "$STARTSEQ" "$NOPIC" "$THR_END" "$R_PERMA" "$SETFLIP_AFTER" "$PAD_TOTAL" "$ELO_STOPPED"
echo "log: $LOG_PATH"

if [ "$ELO_STOPPED" = "nenhum" ]; then
  exit 0
else
  exit 1
fi
