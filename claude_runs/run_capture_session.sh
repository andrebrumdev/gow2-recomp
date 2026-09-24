#!/bin/bash
# run_capture_session.sh BIN LOG STEM [PS3_X=V ...]
# One GoW2 session PLAYED BY THE USER with the launcher env (env_gow2.sh), pad autostart OFF, the RSX recorder in
# trigger mode and the NV3089 trace on:
#   PS3_RSX_CAPTURE=$G/rsx_captures/STEM.rsxc:0:${CAP_FRAMES:-4}
#   PS3_RSX_CAPTURE_TRIGGER=$G/rsx_captures/.capture_now  PS3_RSX_CAPTURE_MAX=${CAP_MAX:-6}  PS3_TRACE_GCM2D=1
# Each `touch $G/rsx_captures/.capture_now` records the next CAP_FRAMES frames into rsx_captures/STEM_<k>.rsxc
# (+ STEM_<k>_live_*.bmp). SESSION_FULLSCREEN (0|1, default 0) and SESSION_MUTE (0|1, default 0) follow the user's
# choice. Runs until the game exits (the user closes it) or SESSION_TIMEOUT s (default 3600); kills only its own PID.
# Refuses to start while another "./g2<name> EBOOT" instance runs or when a STEM_<k>.rsxc exists. Prints every
# [RSXCAP] line, the [GCM2D] counts, a Vulkan stats/validation summary (when the backend is Vulkan) and fatal hits.
#   BIN   binary in the gow2-recomp root, name ^g2[a-z0-9]+$ ; LOG claude_runs/LOG.log ; STEM ^[a-z0-9_]+$
set -u
G="$HOME/Documents/PESSOAL/gow2-recomp"
[ "$#" -ge 3 ] || { echo "usage: $0 BIN LOG STEM [PS3_X=V ...]"; exit 2; }
BIN="$1"; LOG="$2"; STEM="$3"; shift 3
[[ "$BIN" =~ ^g2[a-z0-9]+$ ]] || { echo "bad binary name"; exit 2; }
[[ "$LOG" =~ ^[a-z0-9_]+$ ]] || { echo "bad log name"; exit 2; }
[[ "$STEM" =~ ^[a-z0-9_]+$ ]] || { echo "bad stem"; exit 2; }
FR="${CAP_FRAMES:-4}"; MAX="${CAP_MAX:-6}"; TMO="${SESSION_TIMEOUT:-3600}"
FS="${SESSION_FULLSCREEN:-0}"; MUTE="${SESSION_MUTE:-0}"
[[ "$FR" =~ ^[1-8]$ ]] || { echo "bad CAP_FRAMES"; exit 2; }
[[ "$MAX" =~ ^[1-8]$ ]] || { echo "bad CAP_MAX"; exit 2; }
[[ "$TMO" =~ ^[0-9]{1,5}$ ]] || { echo "bad SESSION_TIMEOUT"; exit 2; }
[[ "$FS" =~ ^[01]$ ]] && [[ "$MUTE" =~ ^[01]$ ]] || { echo "bad SESSION_FULLSCREEN / SESSION_MUTE"; exit 2; }
EXTRAS=()
for e in "$@"; do
  [[ "$e" =~ ^PS3_[A-Z0-9_]+=[A-Za-z0-9_.,/-]*$ ]] || { echo "bad extra env: $e"; exit 2; }
  EXTRAS+=("$e")
done
cd "$G" || exit 2
[ -f "$BIN" ] && [ ! -L "$BIN" ] || { echo "binary missing or not a regular file"; exit 2; }
if pgrep -f '^\./g2[a-z0-9]+ EBOOT' > /dev/null; then echo "another GoW2 instance is running:"; pgrep -fl '^\./g2[a-z0-9]+ EBOOT'; exit 2; fi
mkdir -p rsx_captures || exit 2
for k in $(seq 1 "$MAX"); do
  [ ! -e "rsx_captures/${STEM}_$k.rsxc" ] || { echo "capture exists, refusing: rsx_captures/${STEM}_$k.rsxc"; exit 2; }
done
TRIG="$G/rsx_captures/.capture_now"
rm -f "$TRIG"
L="$G/claude_runs/$LOG.log"
env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR=/tmp G="$G" BIN="$BIN" \
  PS3_FULLSCREEN="$FS" PS3_MUTE="$MUTE" PS3_PAD_AUTOSTART=0 PS3_MOVIE_DONE_MS=auto \
  PS3_RSX_CAPTURE="$G/rsx_captures/$STEM.rsxc:0:$FR" PS3_RSX_CAPTURE_TRIGGER="$TRIG" PS3_RSX_CAPTURE_MAX="$MAX" \
  PS3_TRACE_GCM2D=1 \
  ${EXTRAS[@]+"${EXTRAS[@]}"} \
  bash -c 'cd "$G" && . ./env_gow2.sh && exec ./"$BIN" EBOOT.ELF' > "$L" 2>&1 &
PID=$!
echo "pid=$PID log=$L stem=$STEM frames=$FR max=$MAX trigger=$TRIG"
n=0
while kill -0 "$PID" 2>/dev/null && [ "$n" -lt "$TMO" ]; do sleep 5; n=$((n + 5)); done
if kill -0 "$PID" 2>/dev/null; then
  echo "timeout ${TMO}s: stopping pid $PID"; kill -TERM "$PID" 2>/dev/null; sleep 5; kill -9 "$PID" 2>/dev/null
fi
rm -f "$TRIG"
echo "--- RSXCAP"; grep '\[RSXCAP\]' "$L"
NB=$(grep -c '^\[GCM2D\] blit' "$L"); NG=$(grep '^\[GCM2D\] blit' "$L" | grep -c ': GPU$'); NC=$(grep '^\[GCM2D\] blit' "$L" | grep -c ': cpu$')
echo "--- GCM2D blits=$NB GPU=$NG cpu=$NC (first 48 only)"; grep '^\[GCM2D\] blit' "$L" | head -5
if grep -q '\[RSX vulkan\] stats' "$L"; then
  echo "--- vulkan stats"; grep '\[RSX vulkan\] stats' "$L" | head -3; grep '\[RSX vulkan\] stats' "$L" | tail -3
  python3 - "$L" <<'PY'
import re, sys
F = ["skip", "shader_fail", "no_shader", "ring_full", "tex_skip", "feedback_skip", "blit_skip", "restart_list_skip",
     "pso_fail", "mrt_skip", "desc_full", "dropped", "depth_conv_skip", "mrt_variant_lost"]
mx = dict.fromkeys(F, 0); tot = {}; n = 0
for line in open(sys.argv[1], errors="replace"):
    if "[RSX vulkan] stats" not in line:
        continue
    n += 1
    head, _, tail = line.partition(" tot:")
    for f in F:
        m = re.search(r" %s=(\d+)" % f, head)
        if m:
            mx[f] = max(mx[f], int(m.group(1)))
    tot = {f: int(v) for f, v in re.findall(r" ([a-z_]+):(\d+)", " " + tail)}
print("stats lines=%d frame max: %s" % (n, " ".join("%s=%d" % (f, mx[f]) for f in F)))
print("last tot: %s" % " ".join("%s:%d" % (f, tot.get(f, -1)) for f in F))
bad = [f for f in F if mx[f] or tot.get(f, 1)]
print("SKIP COUNTERS %s" % ("ZERO" if n and not bad else "NON-ZERO or absent: " + " ".join(bad)))
PY
  echo "--- validation messages: errors=$(grep -c '\[RSX vulkan\]\[validation\] ERROR' "$L") warnings=$(grep -c '\[RSX vulkan\]\[validation\] WARNING' "$L")"
fi
echo "--- fatal"; grep -nE 'FATAL|abort|SIGBUS|SIGSEGV' "$L" | head -5
exit 0
