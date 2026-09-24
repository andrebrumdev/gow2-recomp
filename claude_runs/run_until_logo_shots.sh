#!/bin/bash
# run_until_logo_shots.sh BIN LOG BACKEND SHOTDIR [EXTRA_ENV=VAL]...
# One GoW2 boot in the legacy host-content env (PS3_MOVIE_HLE=1 +
# PS3_BOOT_LOGO_QUEUE=1, windowed, muted, no pad autostart) that dumps the
# host-content (legal / logo) holds to SHOTDIR via PS3_HOST_CONTENT_SHOT, and
# stops once [HC-SHOT] >= WANT_HC_SHOTS (default 3) and [MOVIE-SHOT] >=
# WANT_MOVIE_SHOTS (default 0), on process exit or after SHOT_TIMEOUT s
# (default 150; +5 s for late validation messages). Kills only its own PID.
# Refuses to start while the user plays (g2play / ./g2* EBOOT). Opens a game window.
#   BIN      binary in the gow2-recomp root, name ^g2[a-z0-9]+$
#   LOG      claude_runs/LOG.log, name ^[a-z0-9_]+$
#   BACKEND  metal | vulkan
#   SHOTDIR  directory for the hcN_*.bmp dumps (created)
#   extras   PS3_*=... or VK_*=... (set before env_gow2.sh, which keeps them)
set -u
G="$HOME/Documents/PESSOAL/gow2-recomp"
WH="${WANT_HC_SHOTS:-3}"; WM="${WANT_MOVIE_SHOTS:-0}"; TMO="${SHOT_TIMEOUT:-150}"
[[ "$WH" =~ ^[0-9]$ ]] && [[ "$WM" =~ ^[0-9]$ ]] && [[ "$TMO" =~ ^[0-9]{1,4}$ ]] || { echo "bad WANT_*/SHOT_TIMEOUT"; exit 2; }
if pgrep -x g2play >/dev/null || pgrep -f '^\./g2[a-z0-9]+ EBOOT' >/dev/null; then
  echo "a game instance is running (g2play or ./g2* EBOOT): refusing"; exit 3
fi
[ "$#" -ge 4 ] || { echo "usage: $0 BIN LOG BACKEND SHOTDIR [EXTRA_ENV=VAL]..."; exit 2; }
BIN="$1"; LOG="$2"; BACKEND="$3"; SHOTDIR="$4"; shift 4
[[ "$BIN" =~ ^g2[a-z0-9]+$ ]] || { echo "bad binary name"; exit 2; }
[[ "$LOG" =~ ^[a-z0-9_]+$ ]] || { echo "bad log name"; exit 2; }
case "$BACKEND" in metal|vulkan) ;; *) echo "bad backend"; exit 2 ;; esac
[[ "$SHOTDIR" =~ ^[A-Za-z0-9_./-]+$ ]] || { echo "bad shot dir"; exit 2; }
EXTRAS=()
for e in "$@"; do
  if [[ "$e" =~ ^PS3_[A-Z0-9_]+=[A-Za-z0-9_.,/-]*$ ]] || [[ "$e" =~ ^VK_[A-Z_]+=[A-Za-z0-9_./-]*$ ]]; then
    EXTRAS+=("$e")
  else
    echo "bad extra env: $e"; exit 2
  fi
done
cd "$G" || exit 2
[ -f "$BIN" ] && [ ! -L "$BIN" ] || { echo "binary missing or not a regular file"; exit 2; }
mkdir -p "$SHOTDIR" || exit 2
SHOTDIR="$(cd "$SHOTDIR" && pwd)" || exit 2
L="$G/claude_runs/$LOG.log"
env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR=/tmp G="$G" BIN="$BIN" \
  PS3_RSX_BACKEND="$BACKEND" PS3_MOVIE_HLE=1 PS3_BOOT_LOGO_QUEUE=1 \
  PS3_FULLSCREEN=0 PS3_MUTE=1 \
  PS3_HOST_CONTENT_SHOT="$SHOTDIR" PS3_HOST_CONTENT_SHOT_AT=2 \
  ${EXTRAS[@]+"${EXTRAS[@]}"} \
  bash -c 'cd "$G" && . ./env_gow2.sh && unset PS3_PAD_AUTOSTART && exec ./"$BIN" EBOOT.ELF' \
  > "$L" 2>&1 &
PID=$!
echo "pid=$PID backend=$BACKEND shots=$SHOTDIR log=$L"
n=0
while [ "$n" -lt $((TMO / 2)) ]; do
  sleep 2
  n=$((n + 1))
  if [ "$(grep -c '\[HC-SHOT\]' "$L")" -ge "$WH" ] && [ "$(grep -c '\[MOVIE-SHOT\]' "$L")" -ge "$WM" ]; then
    echo "shots em $((n * 2))s"; break; fi
  if ! kill -0 "$PID" 2>/dev/null; then echo "processo saiu em $((n * 2))s"; break; fi
done
[ "$n" -ge $((TMO / 2)) ] && echo "timeout ${TMO}s"
sleep 5
kill -TERM "$PID" 2>/dev/null
sleep 2
kill -9 "$PID" 2>/dev/null
grep -E '\[HC-SHOT\]|\[MOVIE-SHOT\]|\[CONTENT\]|\[boot\]|\[rsx-bridge\]|\[RSX vulkan\]|\[movie-vt\] decode end|\[RSX metal\] movie stop' "$L"
exit 0
