#!/bin/bash
# run_metrics.sh BIN SHA256 LOG SECS [PS3_X=v ...] -- one windowed GoW2 run (launcher env, muted)
# with PS3_TRACE_FPS + PS3_TRACE_FRAMETIME, sampling RSS/CPU of the process every second
# into LOG.res.csv (t_s,rss_kb,cpu_pct,footprint every 5 s -- compare footprint, not RSS, on macOS)
# and the exit status into LOG.exit. Report: python3 metrics_report.py LOG... (same dir).
set -u
G="$HOME/Documents/PESSOAL/gow2-recomp"; BIN="$1"; WANT="$2"; LOG="$3"; SECS="$4"; shift 4
L="$G/claude_runs/$LOG.log"; R="$G/claude_runs/$LOG.res.csv"; X="$G/claude_runs/$LOG.exit"
cd "$G" || exit 2
[ "$(shasum -a 256 "$BIN" | cut -d' ' -f1)" = "$WANT" ] || { echo "checksum mismatch"; exit 2; }
T=$(mktemp -d /tmp/gow2run.XXXXXX); trap 'rm -rf "$T"' EXIT
cp "$BIN" "$T/boot"; chmod 500 "$T/boot"
env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR=/tmp \
  PS3_VFS_ROOT="$G/extracted/USRDIR" PS3_MOVIE_CACHE="$G/movie_cache" \
  PS3_MOVIE_HLE=1 PS3_NOMOVIES=0 PS3_MOVIE_IO=1 PS3_MOVIE_EOS=1 PS3_VDEC_ASYNC=1 \
  PS3_PAD_AUTOSTART=1 PS3_MUTE=1 PS3_SPU1=1 PS3_RSX_FIFO=1 PS3_RSX_BACKEND=metal \
  PS3_CELLSYS_REORDER=1 PS3_GCM_CB=1 PS3_LWMUTEX_REAL=1 PS3_FIOS_STICKY_OWNER=1 \
  PS3_MOVIE_DONE_MS=3000 PS3_METAL_PER_DRAW_RT=1 PS3_METAL_DEBUG_NODEPTH=0 \
  PS3_METAL_DEBUG_DEPTH=rsx PS3_METAL_DEBUG_CLEAR_FRAME=0 PS3_FULLSCREEN=0 \
  PS3_TRACE_FPS=1 PS3_TRACE_FRAMETIME=1 "$@" \
  "$T/boot" EBOOT.ELF > "$L" 2>&1 &
PID=$!
echo "t_s,rss_kb,cpu_pct,footprint" > "$R"
n=0; st=running
while [ "$n" -lt "$SECS" ]; do
  sleep 1; n=$((n + 1))
  if ! kill -0 "$PID" 2>/dev/null; then st="exited_at_${n}s"; break; fi
  v=$(LC_ALL=C ps -o rss=,%cpu= -p "$PID" 2>/dev/null | awk '{print $1","$2}')
  m=""; [ $((n % 5)) -eq 0 ] && m=$(top -l 1 -pid "$PID" -stats mem 2>/dev/null | tail -1)
  [ -n "$v" ] && echo "$n,$v,$m" >> "$R"
done
if [ "$st" = running ]; then kill -TERM "$PID" 2>/dev/null; sleep 3; kill -9 "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; echo "ran_full" > "$X"
else wait "$PID"; echo "$st rc=$?" > "$X"; fi
echo "$LOG: $(cat "$X")"
