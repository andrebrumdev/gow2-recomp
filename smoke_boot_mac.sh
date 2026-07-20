#!/usr/bin/env bash
# Smoke de baseline do boot nativo macOS/arm64 (Phase 0 do plano
# ps3recomp/docs/superpowers/plans/2026-07-20-gow2-full-bringup.md).
#
# Corre headless e classifica o resultado. Serve para detectar REGRESSAO:
# qualquer mudanca no motor ou no host que faca o boot parar antes do wall
# SPURS conhecido deve reprovar aqui.
#
# PS3_TRACE_SPURS=1 e obrigatorio: as chamadas cellSpurs* so aparecem no log
# atraves do trace de dispatch. Os handlers reais estao em
# runtime/ppu/ppu_sysprx.cpp (ctx-based, BE-aware) e vencem os de libs/spurs,
# que nunca executam -- por isso NAO se deve procurar por linhas "[cellSpurs]".
#
# Uso: ./smoke_boot_mac.sh [segundos]        (default 30)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

SECS="${1:-30}"

if [ ! -x ./boot_gow2 ]; then
    echo "FAIL: boot_gow2 nao existe -- corra ./build_macos.sh" >&2
    exit 1
fi
if [ ! -f EBOOT.ELF ]; then
    echo "FAIL: EBOOT.ELF ausente -- extraia e decripte o PKG" >&2
    exit 1
fi

export PS3_NO_RSX=1 PS3_MOVIE_HLE=1 PS3_NOMOVIES=1 PS3_PAD_AUTOSTART=1
export PS3_RSX_FIFO=1 PS3_CELLSYS_REORDER=1
export PS3_VFS_ROOT="${PS3_VFS_ROOT:-$HERE/extracted/USRDIR}"
export PS3_TRACE_SPURS=1

LOG=$(mktemp /tmp/gow2_smoke.XXXXXX)
./boot_gow2 EBOOT.ELF > "$LOG" 2>&1 &
PID=$!

# Amostra o consumo de CPU perto do fim: distingue "bloqueado" (o esperado)
# de "busy-loop" (regressao para spin em stub).
sleep $(( SECS > 5 ? SECS - 3 : SECS ))
CPU=$(ps -p "$PID" -o %cpu= 2>/dev/null | tr -d ' ' || echo "")
sleep 3
kill -9 "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

fail() { echo "FAIL: $1"; echo "  log: $LOG"; exit 1; }

# --- progresso minimo exigido -------------------------------------------
grep -qE '5[0-9]{4} lifted functions'   "$LOG" || fail "tabela de funcoes nao registada"
grep -q  '151 imports'                  "$LOG" || fail "imports PRX nao resolvidos"
grep -q  '_SPU_printf_server'           "$LOG" || fail "thread do printf server nao criada"
grep -q  'THREAD 1] host thread started' "$LOG" || fail "trampolim de thread do guest nao correu"
grep -q  'cellSpursInitializeWithAttribute' "$LOG" || fail "boot nao chega ao SPURS init"

# --- regressoes proibidas ------------------------------------------------
grep -q 'lv2_syscall 141 (stub)' "$LOG" && fail "sys_timer_usleep voltou a ser stub"
grep -q 'lv2_syscall 144 (stub)' "$LOG" && fail "sys_time_get_timezone voltou a ser stub"

NIDS=$(grep -c 'unresolved NID' "$LOG" || true)
[ "$NIDS" -le 2 ] || fail "NIDs por resolver: $NIDS (limite 2)"

# --- classificacao do wall ----------------------------------------------
SPURS_N=$(grep -c 'cellSpursInitializeWithAttribute' "$LOG" || true)
# ps imprime a percentagem com o separador decimal do locale (1.8 ou 1,8),
# entao corta em qualquer um dos dois antes de comparar como inteiro.
CPU_INT=${CPU%%[.,]*}; CPU_INT=${CPU_INT:-0}
if [ "$CPU_INT" -ge 50 ]; then
    fail "processo em busy-loop (CPU ${CPU}%) -- esperado bloqueado"
fi

echo "PASS: baseline boot reaches SPURS wall (blocked, not stub-spin)"
echo "  cellSpursInitializeWithAttribute: ${SPURS_N}x   unresolved NIDs: ${NIDS}   CPU: ${CPU}%"
rm -f "$LOG"
