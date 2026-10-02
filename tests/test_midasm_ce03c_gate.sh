#!/bin/bash
# The CE03C wait-idle hook must stay OFF by default (PS3_CE03C_WAIT_IDLE=1 restores it): it held the game's 2nd
# Play("SmLogo_v2") until the 1st movie ended, so the logo played twice (found on the Android build, whose copy of
# hooks/gow2_midasm_hooks.cpp had lost the gate). Static check: the gate sits at the top of the function body,
# before the first use of ctx.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; F="$HERE/../hooks/gow2_midasm_hooks.cpp"
fails=0; bad() { echo "FAIL: $*"; fails=$((fails + 1)); }
start="$(grep -n 'void gow2_midasm_Ce03cWaitIdle(ppu_context\* ctx)' "$F" | head -1 | cut -d: -f1)"
[ -n "$start" ] || { echo "FAIL: function not found"; exit 1; }
body="$(sed -n "$((start + 1)),$((start + 14))p" "$F")"
printf '%s\n' "$body" | grep -q 'getenv("PS3_CE03C_WAIT_IDLE")' || bad "the PS3_CE03C_WAIT_IDLE gate is missing at the top of gow2_midasm_Ce03cWaitIdle"
printf '%s\n' "$body" | grep -q 'if (!on) return;' || bad "the gate must return when the env is not 1"
gate_line="$(sed -n "$start,\$p" "$F" | grep -n 'PS3_CE03C_WAIT_IDLE' | head -1 | cut -d: -f1)"
use_line="$(sed -n "$start,\$p" "$F" | grep -n 'ctx->gpr' | head -1 | cut -d: -f1)"
[ -n "$gate_line" ] && [ -n "$use_line" ] && [ "$gate_line" -lt "$use_line" ] || bad "the gate must come before the first use of ctx"
[ "$fails" = 0 ] && { echo "test_midasm_ce03c_gate: PASS"; exit 0; }
echo "test_midasm_ce03c_gate: FAIL ($fails)"; exit 1
