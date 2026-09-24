#!/bin/bash
# run_movie_captures.sh BIN LOG STEM MODE [PS3_X=V ...]
# One GoW2 boot with the launcher env (env_gow2.sh), the RSX recorder in trigger mode, and a watcher that touches the
# trigger at fixed offsets (seconds) after a movie starts:
#   intro     pad autostart OFF; anchor "st620 1 -> 11" (Santa Monica intro, ~10.8 s); MOVIE_OFFSETS default "2 5 8"
#   cutscene  pad autostart ON (New Game, then idle in the cutscene); anchor
#             "Play reached: in-game picture starts now" (introhud, ~125 s); MOVIE_OFFSETS default "5 30 60 95"
#   watch     pad autostart OFF, the user drives: intro offsets (INTRO_OFFSETS, default "2 5 8") then cutscene offsets
#             (CS_OFFSETS, default "5 30 60 95"); SESSION_TIMEOUT default 900 s; SESSION_FULLSCREEN / SESSION_MUTE 0|1
# Each trigger records CAP_FRAMES (default 4) frames into rsx_captures/STEM_<k>.rsxc (+ STEM_<k>_live_*.bmp).
# An offset reached after the movie left Play ("st620 11 -> 0") is skipped and reported. Stops after the last capture's
# live dump (intro/cutscene), process exit or the timeout; kills only its own PID. Refuses while g2play or another
# "./g2<name> EBOOT" runs, or when a STEM_<k>.rsxc exists.
set -u
G="$HOME/Documents/PESSOAL/gow2-recomp"
[ "$#" -ge 4 ] || { echo "usage: $0 BIN LOG STEM MODE [PS3_X=V ...]"; exit 2; }
BIN="$1"; LOG="$2"; STEM="$3"; MODE="$4"; shift 4
[[ "$BIN" =~ ^g2[a-z0-9]+$ ]] || { echo "bad binary name"; exit 2; }
[[ "$LOG" =~ ^[a-z0-9_]+$ ]] || { echo "bad log name"; exit 2; }
[[ "$STEM" =~ ^[a-z0-9_]+$ ]] || { echo "bad stem"; exit 2; }
FR="${CAP_FRAMES:-4}"; [[ "$FR" =~ ^[1-8]$ ]] || { echo "bad CAP_FRAMES"; exit 2; }
FS="${SESSION_FULLSCREEN:-0}"; MUTE="${SESSION_MUTE:-1}"
[[ "$FS" =~ ^[01]$ ]] && [[ "$MUTE" =~ ^[01]$ ]] || { echo "bad SESSION_FULLSCREEN / SESSION_MUTE"; exit 2; }
AS=0; A1=""; O1=""; A2=""; O2=""; TMO=240
case "$MODE" in
  intro)    A1='st620 1 -> 11'; O1="${MOVIE_OFFSETS:-2 5 8}"; TMO=120 ;;
  cutscene) AS=1; A1='Play reached: in-game picture starts now'; O1="${MOVIE_OFFSETS:-5 30 60 95}"; TMO=300 ;;
  watch)    A1='st620 1 -> 11'; O1="${INTRO_OFFSETS:-2 5 8}"
            A2='Play reached: in-game picture starts now'; O2="${CS_OFFSETS:-5 30 60 95}"; TMO="${SESSION_TIMEOUT:-900}" ;;
  *) echo "bad mode"; exit 2 ;;
esac
[[ "$TMO" =~ ^[0-9]{1,5}$ ]] || { echo "bad SESSION_TIMEOUT"; exit 2; }
for o in $O1 $O2; do [[ "$o" =~ ^[0-9]{1,3}$ ]] || { echo "bad offset $o"; exit 2; }; done
NCAP=$(echo $O1 $O2 | wc -w | tr -d ' '); [ "$NCAP" -ge 1 ] && [ "$NCAP" -le 8 ] || { echo "1..8 offsets"; exit 2; }
EXTRAS=()
for e in "$@"; do
  [[ "$e" =~ ^PS3_[A-Z0-9_]+=[A-Za-z0-9_.,/-]*$ ]] || { echo "bad extra env: $e"; exit 2; }
  EXTRAS+=("$e")
done
cd "$G" || exit 2
[ -f "$BIN" ] && [ ! -L "$BIN" ] || { echo "binary missing or not a regular file"; exit 2; }
if pgrep -x g2play > /dev/null || pgrep -f '^\./g2[a-z0-9]+ EBOOT' > /dev/null; then
  echo "a GoW2 instance is running (the user may be playing):"; pgrep -fl 'g2'; exit 2; fi
mkdir -p rsx_captures || exit 2
for k in $(seq 1 "$NCAP"); do
  [ ! -e "rsx_captures/${STEM}_$k.rsxc" ] || { echo "capture exists, refusing: rsx_captures/${STEM}_$k.rsxc"; exit 2; }
done
TRIG="$G/rsx_captures/.capture_now"; rm -f "$TRIG"
L="$G/claude_runs/$LOG.log"
env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR=/tmp G="$G" BIN="$BIN" \
  PS3_FULLSCREEN="$FS" PS3_MUTE="$MUTE" PS3_PAD_AUTOSTART="$AS" PS3_MOVIE_DONE_MS=auto \
  PS3_RSX_CAPTURE="$G/rsx_captures/$STEM.rsxc:0:$FR" PS3_RSX_CAPTURE_TRIGGER="$TRIG" PS3_RSX_CAPTURE_MAX="$NCAP" \
  ${EXTRAS[@]+"${EXTRAS[@]}"} \
  bash -c 'cd "$G" && . ./env_gow2.sh && exec ./"$BIN" EBOOT.ELF' > "$L" 2>&1 &
PID=$!
echo "pid=$PID log=$L stem=$STEM mode=$MODE offsets=[$O1] [$O2] frames=$FR"
T0=$(date +%s)
alive() { kill -0 "$PID" 2>/dev/null && [ $(( $(date +%s) - T0 )) -lt "$TMO" ]; }
fire() {   # fire ANCHOR OFFSETS: wait for the anchor line, then touch the trigger at each offset (s) after it
  # NOTE (Task 1 fix, 2026-09-24): "movie ended" is judged against a baseline of 'st620 11 -> 0' hits taken right
  # after THIS anchor fires, not a fixed 0 -- a prior movie (the intro) already produced one such transition before
  # the cutscene anchor fires, which made every cutscene offset falsely report "movie ended" in the original draft.
  local anchor="$1" offs="$2" t_a o base
  until grep -aqF "$anchor" "$L" 2>/dev/null; do alive || return 1; sleep 0.5; done
  t_a=$(date +%s); echo "anchor '$anchor' at $((t_a - T0)) s"
  base=$(grep -ac 'st620 11 -> 0' "$L")
  for o in $offs; do
    while [ $(( $(date +%s) - t_a )) -lt "$o" ]; do alive || return 1; sleep 0.2; done
    if [ "$(grep -ac 'st620 11 -> 0' "$L")" -gt "$base" ]; then echo "movie ended before offset $o"; continue; fi
    until [ ! -e "$TRIG" ]; do alive || return 1; sleep 0.2; done   # previous trigger consumed
    touch "$TRIG"; echo "trigger at +$o s"
  done
}
fire "$A1" "$O1"
if [ -n "$A2" ]; then fire "$A2" "$O2"; fi
if [ "$MODE" != watch ]; then
  # fire() returned: every trigger was touched. Done when the last one was consumed and every consumed trigger
  # produced its live dump.
  until [ ! -e "$TRIG" ] && [ "$(grep -ac '\[RSXCAP\] trigger seen' "$L")" -ge 1 ] \
        && [ "$(grep -ac '\[RSXCAP\] live dump' "$L")" -ge "$(grep -ac '\[RSXCAP\] trigger seen' "$L")" ]; do
    alive || break; sleep 1
  done
  sleep 2
else
  while alive; do sleep 5; done
fi
if kill -0 "$PID" 2>/dev/null; then kill -TERM "$PID" 2>/dev/null; sleep 3; kill -9 "$PID" 2>/dev/null; fi
rm -f "$TRIG"
echo "--- RSXCAP"; grep '\[RSXCAP\]' "$L"
echo "--- movie"; grep -aE '\[MOVIEFSM\] st620 (1 -> 11|11 -> 0|10 -> 11)|Play reached|cellVdec-vt\] sessao' "$L"
if grep -q '\[RSX vulkan\] stats' "$L"; then
  echo "--- vulkan"; grep '\[RSX vulkan\] stats' "$L" | tail -2
  grep '\[RSX vulkan\] validation (running)' "$L" | tail -1
  echo "validation messages: errors=$(grep -c '\[RSX vulkan\]\[validation\] ERROR' "$L") warnings=$(grep -c '\[RSX vulkan\]\[validation\] WARNING' "$L")"
fi
echo "--- fatal"; grep -aE 'FATAL|SIGBUS|SIGSEGV|abort\(' "$L" | head -5
exit 0
