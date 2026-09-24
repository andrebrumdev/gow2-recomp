#!/bin/bash
# run_until_capture.sh BIN LOG CAPTURE MIN_DRAWS FRAMES [PS3_X=V ...]
# One GoW2 boot with the launcher env (env_gow2.sh: pad autostart ON), windowed
# and muted, with the RSX frame recorder armed:
#   PS3_RSX_CAPTURE=$G/CAPTURE:MIN_DRAWS:FRAMES
# Stops at the recorder's "live dump" line, a "capture aborted" line, process exit
# or 480 s. Kills only its own PID. Opens a game window: ask the user first.
#   BIN      binary in the gow2-recomp root, name ^g2[a-z0-9]+$
#   LOG      claude_runs/LOG.log, name ^[a-z0-9_]+$
#   CAPTURE  rsx_captures/<name>.rsxc (never overwritten)
set -u
G="$HOME/Documents/PESSOAL/gow2-recomp"
[ "$#" -ge 5 ] || { echo "usage: $0 BIN LOG CAPTURE MIN_DRAWS FRAMES [PS3_X=V ...]"; exit 2; }
BIN="$1"; LOG="$2"; CAP="$3"; MIN="$4"; FR="$5"; shift 5
[[ "$BIN" =~ ^g2[a-z0-9]+$ ]] || { echo "bad binary name"; exit 2; }
[[ "$LOG" =~ ^[a-z0-9_]+$ ]] || { echo "bad log name"; exit 2; }
[[ "$CAP" =~ ^rsx_captures/[a-z0-9_]+\.rsxc$ ]] || { echo "bad capture path"; exit 2; }
[[ "$MIN" =~ ^[0-9]{1,4}$ ]] || { echo "bad min draws"; exit 2; }
[[ "$FR" =~ ^[1-8]$ ]] || { echo "bad frame count"; exit 2; }
EXTRAS=()
for e in "$@"; do
  [[ "$e" =~ ^PS3_[A-Z0-9_]+=[A-Za-z0-9_.,/-]*$ ]] || { echo "bad extra env: $e"; exit 2; }
  EXTRAS+=("$e")
done
cd "$G" || exit 2
[ -f "$BIN" ] && [ ! -L "$BIN" ] || { echo "binary missing or not a regular file"; exit 2; }
mkdir -p rsx_captures || exit 2
[ ! -e "$CAP" ] || { echo "capture exists, refusing to overwrite: $CAP"; exit 2; }
L="$G/claude_runs/$LOG.log"
env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR=/tmp G="$G" BIN="$BIN" \
  PS3_FULLSCREEN=0 PS3_MUTE=1 PS3_RSX_CAPTURE="$G/$CAP:$MIN:$FR" \
  ${EXTRAS[@]+"${EXTRAS[@]}"} \
  bash -c 'cd "$G" && . ./env_gow2.sh && exec ./"$BIN" EBOOT.ELF' > "$L" 2>&1 &
PID=$!
echo "pid=$PID capture=$CAP min_draws=$MIN frames=$FR"
n=0
while [ "$n" -lt 240 ]; do
  sleep 2; n=$((n + 1))
  if grep -qE '\[RSXCAP\] (live dump|.*capture aborted)' "$L"; then echo "recorder finished after $((n * 2)) s"; break; fi
  kill -0 "$PID" 2>/dev/null || { echo "process exited"; break; }
done
kill -TERM "$PID" 2>/dev/null; sleep 2; kill -9 "$PID" 2>/dev/null
grep '\[RSXCAP\]' "$L"
exit 0
