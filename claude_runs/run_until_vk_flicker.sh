#!/bin/bash
# run_until_vk_flicker.sh BIN LOG [PS3_X=V ...]
# One GoW2 boot on the Vulkan RSX backend with the launcher env (env_gow2.sh),
# windowed and muted, validation layer ON and the flicker probe ON:
#   PS3_RSX_BACKEND=vulkan PS3_VK_VALIDATION=1 PS3_VK_FLICKER=1 PS3_TRACE_FPS=1
# plus the validated extras (set before env_gow2.sh, whose ":=" defaults then
# leave them alone).
# Stops when a "[VK-FLICKER] ... frames=" line reports mrt_frames >= FLK_FRAMES
# (default 1800), on process exit, or at FLK_TIMEOUT s (default 360). Kills only
# its own PID (TERM, 5 s, KILL). Prints the last 3 periodic [VK-FLICKER] lines,
# every spike line, the first/last 3 "[RSX vulkan] stats" lines, the validation
# message counts and FATAL/abort/SIGBUS/SIGSEGV hits.
# Opens a game window: ask the user first.
#   BIN      binary in the gow2-recomp root, name ^g2[a-z0-9]+$
#   LOG      claude_runs/LOG.log, name ^[a-z0-9_]+$
#   extras   PS3_[A-Z0-9_]+=[A-Za-z0-9_.,/-]*
set -u
G="$HOME/Documents/PESSOAL/gow2-recomp"
[ "$#" -ge 2 ] || { echo "usage: $0 BIN LOG [PS3_X=V ...]"; exit 2; }
BIN="$1"; LOG="$2"; shift 2
[[ "$BIN" =~ ^g2[a-z0-9]+$ ]] || { echo "bad binary name"; exit 2; }
[[ "$LOG" =~ ^[a-z0-9_]+$ ]] || { echo "bad log name"; exit 2; }
FRAMES="${FLK_FRAMES:-1800}"
TMO="${FLK_TIMEOUT:-360}"
[[ "$FRAMES" =~ ^[0-9]{1,6}$ ]] || { echo "bad FLK_FRAMES"; exit 2; }
[[ "$TMO" =~ ^[0-9]{1,5}$ ]] || { echo "bad FLK_TIMEOUT"; exit 2; }
EXTRAS=()
for e in "$@"; do
  [[ "$e" =~ ^PS3_[A-Z0-9_]+=[A-Za-z0-9_.,/-]*$ ]] || { echo "bad extra env: $e"; exit 2; }
  EXTRAS+=("$e")
done
cd "$G" || exit 2
[ -f "$BIN" ] && [ ! -L "$BIN" ] || { echo "binary missing or not a regular file"; exit 2; }
L="$G/claude_runs/$LOG.log"
env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR=/tmp G="$G" BIN="$BIN" \
  PS3_FULLSCREEN=0 PS3_MUTE=1 \
  PS3_RSX_BACKEND=vulkan PS3_VK_VALIDATION=1 PS3_VK_FLICKER=1 PS3_TRACE_FPS=1 \
  ${EXTRAS[@]+"${EXTRAS[@]}"} \
  bash -c 'cd "$G" && . ./env_gow2.sh && exec ./"$BIN" EBOOT.ELF' > "$L" 2>&1 &
PID=$!
echo "pid=$PID log=$L flk_frames=$FRAMES timeout=${TMO}s extras=${EXTRAS[*]+${EXTRAS[*]}}"
t0=$(date +%s)
why="timeout ${TMO} s"
while :; do
  sleep 2
  el=$(( $(date +%s) - t0 ))
  if ! kill -0 "$PID" 2>/dev/null; then why="process exited"; break; fi
  m=$(grep -E '^\[VK-FLICKER\] .*frames=[0-9]+ mrt_frames=' "$L" | tail -1 |
      sed -nE 's/.* mrt_frames=([0-9]+).*/\1/p')
  if [ -n "$m" ] && [ "$m" -ge "$FRAMES" ]; then why="mrt_frames>=$FRAMES (mrt_frames=$m)"; break; fi
  [ "$el" -ge "$TMO" ] && break
done
el=$(( $(date +%s) - t0 ))
echo "stop: $why after ${el} s"
if kill -0 "$PID" 2>/dev/null; then
  kill -TERM "$PID" 2>/dev/null
  for _ in 1 2 3 4 5; do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
  kill -9 "$PID" 2>/dev/null
fi
wait "$PID" 2>/dev/null
echo "--- VK-FLICKER (probe line, last 3 periodic, final)"
grep -E '^\[VK-FLICKER\] (probe|disabled)' "$L"
grep -E '^\[VK-FLICKER\] frames=' "$L" | tail -3
grep -E '^\[VK-FLICKER\] final' "$L"
echo "--- VK-FLICKER spikes ($(grep -c '^\[VK-FLICKER\] spike' "$L"))"
grep -E '^\[VK-FLICKER\] spike' "$L"
echo "--- stats (first 3 / last 3)"
grep -E '^\[RSX vulkan\] stats f=' "$L" | head -3
echo "..."
grep -E '^\[RSX vulkan\] stats f=' "$L" | tail -3
grep -E '^\[RSX vulkan\] stats total' "$L"
echo "--- validation"
grep -E '^\[RSX vulkan\] validation' "$L"
echo "validation messages: errors=$(grep -c '\[RSX vulkan\]\[validation\] ERROR' "$L") warnings=$(grep -c '\[RSX vulkan\]\[validation\] WARNING' "$L")"
echo "--- FATAL/abort/SIGBUS/SIGSEGV"
grep -nE 'FATAL|abort|Abort|SIGBUS|SIGSEGV' "$L" | head -10
exit 0
