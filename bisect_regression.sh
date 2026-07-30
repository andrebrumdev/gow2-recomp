#!/usr/bin/env bash
# bisect_regression.sh -- entrega DIAG-01/REG-01 da Fase 6 (marco v1.1):
# um unico comando que corre a recipe menu-fast Metal contra binarios
# boot_gow2* ja guardados e imprime + grava uma tabela com StartSeq,
# thr_auto_load end, R_PermA, REPLAY-NOPIC e contagem de linhas por
# binario. Fecha a janela entre boot_gow2.pre_v3 (funciona) e
# boot_gow2_v4 (falha) sem depender de inspeccao visual de log.
#
# Base literal: o padrao ja validado nesta sessao de planeamento
# ($CLAUDE_JOB_DIR/tmp/bisect_seed.sh, identico byte-a-byte a
# run_probes_metal.sh -- mesmo md5) -- a recipe menu-fast Metal, o loop
# de poll por segundo, e a paragem por PID (TERM -> espera -> -9, NUNCA
# pkill -f, D-5.5/CLAUDE.md, ja derrubou a maquina com load 75).
#
# Uso:
#   ./bisect_regression.sh --bin CAMINHO [LOG] [TIMEOUT]
#       mede um unico binario, imprime uma linha da tabela.
#   ./bisect_regression.sh [TSV_PATH]
#       corre a lista fixa dos 9 binarios conhecidos desta sessao,
#       imprime a tabela completa e grava em TSV (default
#       /tmp/bisect_regression_<timestamp>.tsv).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE" || exit 1

[ -f EBOOT.ELF ] || { echo "ERRO: falta EBOOT.ELF em $HERE" >&2; exit 2; }
[ -f env_gow2.sh ] || { echo "ERRO: falta env_gow2.sh em $HERE" >&2; exit 2; }

set -a; . "$HERE/env_gow2.sh"; set +a

export PS3_VDEC_ASYNC=1
export PS3_VDEC_FORCE_SEQDONE_MS=1500
export PS3_MOVIE_EOS=1 PS3_MOVIE_HLE=1 PS3_MOVIE_IO=1
export PS3_BOOT_LOGO_MS=300
export PS3_AUTO_LOAD_RUN=1
export PS3_PAD_AUTOSTART=1
export PS3_TYPE15_UNSTICK=1
export PS3_SPU1=1 PS3_SPU4=1 PS3_SPU5=1
export PS3_RSX_BACKEND=metal
export PS3_RSX_FIFO=1
export PS3_FULLSCREEN=0
export PS3_PERF_FSM=1

# ---- lista fixa dos 9 binarios conhecidos desta sessao (modo lista) -------
DEFAULT_BINS=(
  boot_gow2.rdy0_ref
  boot_gow2.wip
  boot_gow2.pre_v3
  boot_gow2.pre_v4
  boot_gow2_v3fix
  boot_gow2_v4
  boot_gow2.pre_20260729_150649
  boot_gow2_relift_test
  boot_gow2
)

# ---- measure_one BIN_PATH LOG_PATH TIMEOUT --------------------------------
# Lanca BIN_PATH EBOOT.ELF em fundo, guarda o PID, poll a cada segundo com
# kill -0 ate TIMEOUT (default 90s, o mesmo do run_probes_metal.sh), e no
# fim manda kill -TERM, espera 1s, kill -9, e wait. Nunca pkill -f.
measure_one() {
  local bin_path="$1" log_path="$2" timeout="${3:-90}"

  "$bin_path" EBOOT.ELF > "$log_path" 2>&1 &
  local bpid=$!

  local i
  for ((i = 0; i < timeout; i++)); do
    kill -0 "$bpid" 2>/dev/null || break
    sleep 1
  done

  if kill -0 "$bpid" 2>/dev/null; then
    kill -TERM "$bpid" 2>/dev/null
    sleep 1
    kill -0 "$bpid" 2>/dev/null && kill -9 "$bpid" 2>/dev/null
  fi
  wait "$bpid" 2>/dev/null
}

# ---- extract_counts LOG_PATH -> imprime 5 numeros separados por espaco ----
# grep -c ja imprime 0 quando nao ha match (exit 1, stdout "0"); capturar
# so' com VAR=$(grep -c ...), sem encadear "|| echo 0" a seguir (isso
# duplicaria o 0).
extract_counts() {
  local log_path="$1"
  local log_lines startseq thr_end r_perma nopic

  log_lines=$(wc -l < "$log_path" 2>/dev/null | tr -d ' ')
  log_lines=${log_lines:-0}
  startseq=$(grep -c 'StartSeq(handle=' "$log_path" 2>/dev/null)
  thr_end=$(grep -c 'thr_auto_load() end' "$log_path" 2>/dev/null)
  r_perma=$(grep -c 'R_PermA full flagged' "$log_path" 2>/dev/null)
  nopic=$(grep -c 'REPLAY-NOPIC' "$log_path" 2>/dev/null)

  echo "$log_lines $startseq $thr_end $r_perma $nopic"
}

# ---- classify LOG_LINES THR_END -> imprime a classe -----------------------
# log_lines < 200 -> STRUCTURAL_FAIL (a familia dos ~55-101 linhas que o
# CLAUDE.md documenta como falha estrutural -- nunca um binario que correu
# a recipe ate ao fim; todas as corridas saudaveis desta sessao tem
# >=3161 linhas). Senao thr_end>=1 -> OK; senao REGRESSAO.
classify() {
  local log_lines="$1" thr_end="$2"
  if [ "$log_lines" -lt 200 ]; then
    echo "STRUCTURAL_FAIL"
  elif [ "$thr_end" -ge 1 ]; then
    echo "OK"
  else
    echo "REGRESSAO"
  fi
}

# ---- linha da tabela (mesma ordem nos dois modos) --------------------------
# bin build_date log_lines startseq thr_auto_load_end r_perma_full replay_nopic class
print_row() {
  local bin_name="$1" build_date="$2" log_lines="$3" startseq="$4" thr_end="$5" r_perma="$6" nopic="$7" class="$8"
  printf '%-32s %-14s %9s %9s %18s %13s %13s %s\n' \
    "$bin_name" "$build_date" "$log_lines" "$startseq" "$thr_end" "$r_perma" "$nopic" "$class"
}

print_header() {
  print_row "bin" "build_date" "log_lines" "startseq" "thr_auto_load_end" "r_perma_full" "replay_nopic" "class"
}

tsv_row() {
  local bin_name="$1" build_date="$2" log_lines="$3" startseq="$4" thr_end="$5" r_perma="$6" nopic="$7" class="$8"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$bin_name" "$build_date" "$log_lines" "$startseq" "$thr_end" "$r_perma" "$nopic" "$class"
}

# ============================================================================
# modo --bin: mede um unico binario, imprime uma linha
# ============================================================================
if [ "${1:-}" = "--bin" ]; then
  BIN_PATH="${2:-}"
  if [ -z "$BIN_PATH" ]; then
    echo "ERRO: --bin precisa de um caminho de binario" >&2
    exit 2
  fi
  if [ ! -x "$BIN_PATH" ]; then
    echo "ERRO: binario inexistente ou nao executavel: $BIN_PATH" >&2
    exit 2
  fi
  # bash so' procura em PATH quando o nome nao tem "/" -- resolver para
  # caminho absoluto para nunca depender do PATH do operador.
  case "$BIN_PATH" in
    */*) : ;;
    *) BIN_PATH="$HERE/$BIN_PATH" ;;
  esac
  LOG_PATH="${3:-/tmp/bisect_regression_$(basename "$BIN_PATH")_$(date +%Y%m%d_%H%M%S).log}"
  TIMEOUT="${4:-90}"

  BIN_NAME="$(basename "$BIN_PATH")"
  BUILD_DATE="$(stat -f '%Sm' -t '%d %b %H:%M' "$BIN_PATH" 2>/dev/null || echo '?')"

  measure_one "$BIN_PATH" "$LOG_PATH" "$TIMEOUT"
  read -r LOG_LINES STARTSEQ THR_END R_PERMA NOPIC <<< "$(extract_counts "$LOG_PATH")"
  CLASS="$(classify "$LOG_LINES" "$THR_END")"

  print_header
  print_row "$BIN_NAME" "$BUILD_DATE" "$LOG_LINES" "$STARTSEQ" "$THR_END" "$R_PERMA" "$NOPIC" "$CLASS"
  echo "log: $LOG_PATH"
  exit 0
fi

# ============================================================================
# modo lista: corre os 9 binarios conhecidos, imprime + grava TSV
# ============================================================================
TSV="${1:-/tmp/bisect_regression_$(date +%Y%m%d_%H%M%S).tsv}"

{
  printf 'bin\tbuild_date\tlog_lines\tstartseq\tthr_auto_load_end\tr_perma_full\treplay_nopic\tclass\n'
} > "$TSV"

print_header
for bin_rel in "${DEFAULT_BINS[@]}"; do
  bin_path="$HERE/$bin_rel"
  if [ ! -x "$bin_path" ]; then
    echo "AVISO: $bin_rel nao existe ou nao e executavel -- a saltar" >&2
    continue
  fi

  log_path="/tmp/bisect_regression_${bin_rel}_$(date +%Y%m%d_%H%M%S).log"
  build_date="$(stat -f '%Sm' -t '%d %b %H:%M' "$bin_path" 2>/dev/null || echo '?')"

  measure_one "$bin_path" "$log_path" 90
  read -r log_lines startseq thr_end r_perma nopic <<< "$(extract_counts "$log_path")"
  class="$(classify "$log_lines" "$thr_end")"

  print_row "$bin_rel" "$build_date" "$log_lines" "$startseq" "$thr_end" "$r_perma" "$nopic" "$class"
  tsv_row "$bin_rel" "$build_date" "$log_lines" "$startseq" "$thr_end" "$r_perma" "$nopic" "$class" >> "$TSV"
done

echo "-----"
echo "tsv: $TSV"
# pgrep -f boot_gow2 apanha FALSOS POSITIVOS: watchers de shell doutras
# sessoes cujo COMANDO contem a substring "boot_gow2" (ex.: um loop "until
# ! pgrep -f boot_gow2..."), sem ser eles proprios o binario. pgrep -x
# compara o NOME do processo (argv[0] basename), nao a linha de comando
# inteira -- um zsh/bash nunca casa "boot_gow2*" por -x. Medido: 5 falsos
# positivos com -f contra 0 reais com -x, na mesma maquina, na mesma sessao.
orfaos=0
for bin_rel in "${DEFAULT_BINS[@]}"; do
  n=$(pgrep -x "$bin_rel" 2>/dev/null | wc -l | tr -d ' ')
  orfaos=$((orfaos + n))
done
echo "orfaos_pos_run (pgrep -x por nome exacto de cada binario, sem falsos positivos de watchers de shell): $orfaos"
exit 0
