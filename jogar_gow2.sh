#!/bin/bash
# jogar_gow2.sh -- play God of War II (no timeout, unlike rodar_gow2.sh).
# Keyboard: WASD = left stick, mouse = right stick (camera), arrows = D-pad,
# Space/E/J/K = Cross/Circle/Square/Triangle, L-Shift/Q = L1/R1,
# L-Ctrl/R = L2/R2, F/G (or middle mouse) = L3/R3, Enter/Tab = Start/Select.
# Left/right mouse buttons = Square/Triangle. Controllers work when plugged in.
# The first real key/button turns off the bring-up virtual pad.
#
# The log goes to claude_runs/jogar.log. PS3_TRACE_PROMPT_SHAPES=1 records each
# on-screen button prompt shape once, so new prompts (Circle/Square/L1...) can
# be mapped later; it only logs, it changes nothing on screen.
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
set -a
. "$HERE/env_gow2.sh"
set +a
export PS3_TRACE_PROMPT_SHAPES="${PS3_TRACE_PROMPT_SHAPES:-1}"
mkdir -p "$HERE/claude_runs"
echo "[jogar] log: $HERE/claude_runs/jogar.log"
exec ./boot_gow2 EBOOT.ELF > "$HERE/claude_runs/jogar.log" 2>&1
