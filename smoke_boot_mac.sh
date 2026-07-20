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

. "$HERE/env_gow2.sh"          # env canonico partilhado com rodar_gow2.sh
export PS3_NO_RSX=1            # headless: exercita o caminho CPU/SPURS
export PS3_TRACE_SPURS=1       # obrigatorio: ver o cabecalho deste ficheiro

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
grep -q  'cellSpursInitializeWithAttribute' "$LOG" || fail "boot nao chega ao SPURS init"
grep -q  '\[spurs kernel\] started'     "$LOG" || fail "o kernel SPURS HLE nao arrancou"
# Task 3.3: as imagens SPU liftadas tem de estar ligadas E registadas. spu0 entra
# sempre; spu1/2/3 sao opt-in (PS3_SPU1/2/3, PS3_SPU_ALL). Se o constructor de
# gow2_spu_register.c deixar de correr, ou um simbolo spuN_* sumir do link, e aqui
# que se ve -- caso contrario uma imagem ausente e indistinguivel de uma que
# simplesmente nunca e despachada (o boot regista AddWorkload=0).
grep -q "\[spu_workload\] registered 'gow2_spu0'" "$LOG" || fail "imagem SPU spu0 nao registada"

# O SPURS tem de receber um ponteiro VALIDO: com spurs=0 o handler so faz memset
# e o titulo perde o contexto todo. Foi o que o tblsize_guard passou a corrigir
# (ver runtime/ppu/ppu_loader.cpp) -- se voltar a 0x0, e regressao desse fix.
grep -q  'cellSpursInitializeWithAttribute(r3=0x0 ' "$LOG" && fail "SPURS inicializado com spurs=NULL"

# NAO se exige '_SPU_printf_server' / 'host thread started' (medido 2026-07-20,
# pos-merge): o tblsize_guard bloqueia o zero-write em [0x572BB0], e esse bloqueio
# suprime a criacao da thread pelo guest. Com PS3_NO_TBLSIZE_GUARD=0x572BB0 a
# thread volta E os ponteiros SPURS continuam validos -- mas 0x572BB0 faz parte
# do bloco de config do alocador de bins que o guard existe para proteger no
# Windows, onde o boot vai muito mais longe e nao pudemos medir. Fica o gate para
# esse A/B; a thread e um daemon que dorme para sempre em event_queue_receive(q=1)
# e nao move o wall, entao a sua ausencia nao reprova o baseline.
# Detalhe: notes/2026-07-20-postmerge-rebaseline.md

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
