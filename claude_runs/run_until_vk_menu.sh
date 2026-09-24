#!/bin/bash
# run_until_vk_menu.sh BIN LOG CAPTURE
# One GoW2 boot on the Vulkan RSX backend with the launcher env (env_gow2.sh: pad
# autostart ON), windowed and muted, validation layer ON, and the RSX frame
# recorder armed on the first game-drawn frames (legal/logo screens):
#   PS3_RSX_BACKEND=vulkan PS3_VK_VALIDATION=1 PS3_TRACE_FPS=1
#   PS3_RSX_CAPTURE=$G/CAPTURE:1:4
# (set before env_gow2.sh, whose ":=" defaults then leave them alone).
# Stops when three consecutive per-interval "[RSX vulkan] stats f=" lines report
# draws>=140 (title/menu reached), on process exit, or at 300 s. Kills only its
# own PID. Prints the [RSXCAP] lines, the first/last 3 stats lines, the
# validation summary/messages count and the [FPS] lines.
# Opens a game window: ask the user first.
#   BIN      binary in the gow2-recomp root, name ^g2[a-z0-9]+$
#   LOG      claude_runs/LOG.log, name ^[a-z0-9_]+$
#   CAPTURE  rsx_captures/<name>.rsxc (never overwritten)
set -u
G="$HOME/Documents/PESSOAL/gow2-recomp"
[ "$#" -eq 3 ] || { echo "usage: $0 BIN LOG CAPTURE"; exit 2; }
BIN="$1"; LOG="$2"; CAP="$3"
[[ "$BIN" =~ ^g2[a-z0-9]+$ ]] || { echo "bad binary name"; exit 2; }
[[ "$LOG" =~ ^[a-z0-9_]+$ ]] || { echo "bad log name"; exit 2; }
[[ "$CAP" =~ ^rsx_captures/[a-z0-9_]+\.rsxc$ ]] || { echo "bad capture path"; exit 2; }
cd "$G" || exit 2
[ -f "$BIN" ] && [ ! -L "$BIN" ] || { echo "binary missing or not a regular file"; exit 2; }
mkdir -p rsx_captures || exit 2
[ ! -e "$CAP" ] || { echo "capture exists, refusing to overwrite: $CAP"; exit 2; }
L="$G/claude_runs/$LOG.log"
env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR=/tmp G="$G" BIN="$BIN" \
  PS3_FULLSCREEN=0 PS3_MUTE=1 \
  PS3_RSX_BACKEND=vulkan PS3_VK_VALIDATION=1 PS3_TRACE_FPS=1 \
  PS3_RSX_CAPTURE="$G/$CAP:1:4" \
  bash -c 'cd "$G" && . ./env_gow2.sh && exec ./"$BIN" EBOOT.ELF' > "$L" 2>&1 &
PID=$!
echo "pid=$PID capture=$CAP log=$L"
t0=$(date +%s)
why="timeout 300 s"
while :; do
  sleep 2
  el=$(( $(date +%s) - t0 ))
  if ! kill -0 "$PID" 2>/dev/null; then why="process exited"; break; fi
  # last three per-interval stats lines (not the shutdown "stats total" line)
  n=$(grep -E '^\[RSX vulkan\] stats f=' "$L" | tail -3 |
      sed -nE 's/.* draws=([0-9]+).*/\1/p' | awk '$1 >= 140' | wc -l | tr -d ' ')
  if [ "$n" -ge 3 ]; then why="3 consecutive stats lines with draws>=140"; break; fi
  [ "$el" -ge 300 ] && break
done
el=$(( $(date +%s) - t0 ))
echo "stop: $why after ${el} s"
if kill -0 "$PID" 2>/dev/null; then
  kill -TERM "$PID" 2>/dev/null
  for _ in 1 2 3 4 5; do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
  kill -9 "$PID" 2>/dev/null
fi
wait "$PID" 2>/dev/null
echo "--- RSXCAP"
grep '\[RSXCAP\]' "$L"
echo "--- stats (first 3 / last 3)"
grep -E '^\[RSX vulkan\] stats f=' "$L" | head -3
echo "..."
grep -E '^\[RSX vulkan\] stats f=' "$L" | tail -3
grep -E '^\[RSX vulkan\] stats total' "$L"
echo "--- validation"
grep -E '^\[RSX vulkan\] validation' "$L"
echo "validation messages: errors=$(grep -c '\[RSX vulkan\]\[validation\] ERROR' "$L") warnings=$(grep -c '\[RSX vulkan\]\[validation\] WARNING' "$L")"
echo "--- FPS"
grep '\[FPS\]' "$L" | head -20
echo "--- abort/FATAL"
grep -nE 'FATAL|abort|Abort|SIGBUS|SIGSEGV' "$L" | head -10
exit 0
