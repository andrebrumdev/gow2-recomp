#!/usr/bin/env bash
# smoke_chain_gate.sh -- GATE-01/GATE-02 (Fase 7, marco v1.1): mede a cadeia
# completa do boot (intro -> 2o movie -> re-Play -> AUTO_LOAD -> WAD) --
# nao so' o st620 (o buraco medido em 07-CONTEXT.md: o smoke do v1.0 passa
# com st620=11 num binario que nao desenha um unico frame depois da intro).
#
# Uso:
#   ./smoke_chain_gate.sh --bin BIN_PATH [RUNS] [TSV]
#       mede um binario ja construido, sem rebuild -- e o modo que serve
#       para a prova de GATE-01 contra binarios reais guardados
#       (boot_gow2, boot_gow2.pre_v3), que so existem como binario.
#   ./smoke_chain_gate.sh [LIFT_REL] [RUNS] [TSV]   (default recomp_macos_v3/6)
#       builda o binario a partir do lift candidato (FORCE_REBUILD_LIFT=1,
#       nunca corre um binario desactualizado) e mede-o.
#
# IMPORTANTE (isolamento entre planos paralelos, mesma wave da Fase 7): o
# modo LIFT_REL nunca builda a partir de recomp_macos_v2 -- o Plano 07-03
# edita recomp_macos_v2/ppu_recomp_000.cpp em paralelo, e um build a partir
# dele agora leria um estado a meio de edicao.
#
# rc final: 0 se elo_stopped="nenhum" (os 5 elos bloqueantes passam) em
# >= THRESHOLD=(RUNS*2+2)/3 corridas; 1 senao. Uma corrida com elo_stopped
# != nenhum NUNCA e reclassificada como OK.
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

# ---- parsing de argumentos (duas formas, mesmo contrato de smoke_relift_equiv.sh) --
BIN_OVERRIDE=""
LIFT_REL=""
if [ "${1:-}" = "--bin" ]; then
  BIN_OVERRIDE="${2:-}"
  if [ -z "$BIN_OVERRIDE" ]; then
    echo "ERRO: --bin precisa de um caminho de binario" >&2
    exit 2
  fi
  shift 2
else
  LIFT_REL="${1:-recomp_macos_v3}"
  [ -n "${1:-}" ] && shift
fi
RUNS="${1:-6}"
TSV="${2:-/tmp/chain_gate_$(basename "${LIFT_REL:-$BIN_OVERRIDE}")_$(date +%Y%m%d_%H%M%S).tsv}"
TIMEOUT="${PS3_CHAIN_GATE_TIMEOUT:-90}"

# ---- resolucao do binario ----------------------------------------------------
if [ -n "$BIN_OVERRIDE" ]; then
  BIN="$BIN_OVERRIDE"
  # bash so' procura em PATH quando o nome nao tem "/" -- resolver para
  # caminho absoluto para nunca depender do PATH do operador.
  case "$BIN" in
    */*) : ;;
    *) BIN="$HERE/$BIN" ;;
  esac
  if [ ! -x "$BIN" ]; then
    echo "ERRO: binario inexistente ou nao executavel: $BIN" >&2
    exit 2
  fi
  TAG="$(basename "$BIN")"
else
  case "$LIFT_REL" in
    recomp_macos_v2|./recomp_macos_v2)
      echo "ERRO: smoke_chain_gate.sh nao builda a partir de recomp_macos_v2 -- o Plano 07-03 desta mesma fase edita-o em paralelo (mesma wave). Usa --bin com um binario ja construido." >&2
      exit 2
      ;;
  esac
  LIFT="$HERE/${LIFT_REL#./}"
  if [ ! -d "$LIFT" ]; then
    echo "ERRO: dir de lift nao existe: $LIFT" >&2
    exit 2
  fi
  TAG="$(basename "$LIFT")"
  BIN="$HERE/boot_gow2_${TAG#recomp_macos_}"
  echo "=== a construir $BIN a partir de $LIFT (FORCE_REBUILD_LIFT=1) ==="
  OUT="$BIN" FORCE_REBUILD_LIFT=1 "$HERE/build_macos.sh" "$LIFT"
  build_rc=$?
  if [ "$build_rc" -ne 0 ]; then
    echo "ERRO: build_macos.sh falhou (rc=$build_rc) para $LIFT -- nao vou correr um binario desactualizado" >&2
    exit "$build_rc"
  fi
fi

# ---- SetFlip_after_R_Perm / Pad_total via count_gate() de count_menu_gate.py -
# Nunca reimplementar estes dois greps aqui.
count_gate_pair() {
  local log_path="$1"
  python3 - "$HERE" "$log_path" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from count_menu_gate import count_gate
d = count_gate(sys.argv[2])
print(d["SetFlip_after_R_Perm"], d["Pad_total"])
PY
}

# ---- deriva elo_stopped andando pela cadeia por ORDEM, parando no PRIMEIRO
# elo cujo valor nao bate o "bom". Os elos 6/7 (SetFlip_after_R_Perm/
# Pad_total) sao sempre impressos mas NAO decidem elo_stopped nem o rc.
derive_elo_stopped() {
  local st620="$1" startseq="$2" nopic="$3" thr_end="$4" r_perma="$5"
  if [ "${st620:-0}" -lt 3 ] 2>/dev/null; then
    echo "intro (st620)"
  elif [ "${startseq:-0}" -lt 2 ] 2>/dev/null; then
    echo "2o movie (StartSeq)"
  elif [ "${nopic:-0}" -lt 4 ] 2>/dev/null; then
    echo "re-Play (NOPIC)"
  elif [ "${thr_end:-0}" -lt 1 ] 2>/dev/null; then
    echo "AUTO_LOAD (thr_end)"
  elif [ "${r_perma:-0}" -lt 1 ] 2>/dev/null; then
    echo "WAD (R_PermA)"
  else
    echo "nenhum"
  fi
}

# ---- TSV: cabecalho (trunca se ja existir) ---------------------------------
if [ -n "$TSV" ]; then
  printf 'run\tst620\tstartseq\tnopic\tthr_end\tr_perma\tsetflip_after_rperm\tpad_total\telo_stopped\tclass\n' > "$TSV"
fi

set -a; . "$HERE/env_gow2.sh"; set +a
arm_menu_fast_recipe

OK_COUNT=0
ELO_FAILS=""
for r in $(seq 1 "$RUNS"); do
  LOG="/tmp/chain_gate_${TAG}_run${r}_$(date +%Y%m%d_%H%M%S).log"
  measure_one "$BIN" "$LOG" "$TIMEOUT"

  read -r LOG_LINES STARTSEQ THR_END R_PERMA NOPIC <<< "$(extract_counts "$LOG")"
  ST620="$(extract_st620 "$LOG")"
  read -r SETFLIP_AFTER PAD_TOTAL <<< "$(count_gate_pair "$LOG")"
  SETFLIP_AFTER=${SETFLIP_AFTER:-0}
  PAD_TOTAL=${PAD_TOTAL:-0}

  ELO_STOPPED="$(derive_elo_stopped "$ST620" "$STARTSEQ" "$NOPIC" "$THR_END" "$R_PERMA")"
  if [ "$ELO_STOPPED" = "nenhum" ]; then
    CLASS="OK"
    OK_COUNT=$((OK_COUNT + 1))
  else
    CLASS="REGRESSAO"
    ELO_FAILS="$ELO_FAILS
$ELO_STOPPED"
  fi

  printf "run%d  st620=%s startseq=%s nopic=%s thr_end=%s r_perma=%s setflip_after_rperm=%s pad_total=%s elo_stopped=%s class=%s\n" \
    "$r" "$ST620" "$STARTSEQ" "$NOPIC" "$THR_END" "$R_PERMA" "$SETFLIP_AFTER" "$PAD_TOTAL" "$ELO_STOPPED" "$CLASS"
  echo "log: $LOG"

  if [ -n "$TSV" ]; then
    printf '%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$r" "$ST620" "$STARTSEQ" "$NOPIC" "$THR_END" "$R_PERMA" "$SETFLIP_AFTER" "$PAD_TOTAL" "$ELO_STOPPED" "$CLASS" >> "$TSV"
  fi
done

# THRESHOLD generaliza ">=4 de 6" para outros N, mesma aritmetica de
# smoke_relift_equiv.sh: (RUNS*2+2)/3 -- RUNS=6 -> THRESHOLD=4.
THRESHOLD=$(( (RUNS * 2 + 2) / 3 ))

echo "-----"
printf "elo_stopped=nenhum em %d de %d (limiar: %d)\n" "$OK_COUNT" "$RUNS" "$THRESHOLD"

if [ -n "$ELO_FAILS" ]; then
  FREQ_ELO="$(printf '%s\n' "$ELO_FAILS" | sed '/^$/d' | sort | uniq -c | sort -rn | head -1 | sed 's/^ *[0-9]* //')"
  echo "elo_stopped mais frequente (corridas que falharam): $FREQ_ELO"
fi

echo "tsv: $TSV"

# rc final: 0 so' se OK_COUNT >= THRESHOLD. Nunca reclassifica uma corrida
# com elo_stopped != nenhum como OK para este calculo.
if [ "$OK_COUNT" -ge "$THRESHOLD" ]; then
  exit 0
else
  exit 1
fi
