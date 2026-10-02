#!/bin/bash
# run_perf.sh OUT_DIR [--seconds N] [--timed N] [--env K=V]... [--simpleperf] [--drive|--drive-newgame] [--p50 N] [--p5 N] [--dry-run]
# Android measurement run (spec 2026-09-30, B0/A0). Window mode (default) waits for N gameplay seconds
# ([FPS] lines with draws >= 400) and writes report.md with perf_report.py --tag ANDPERF; --timed N just
# runs N seconds and pulls the log (movie/oracle runs). The app's gow2.override.env is ALWAYS removed and
# the app stopped on exit. Needs the tablet on USB power; run on a Mac on AC power.
# --drive-newgame: drive_gameplay.sh --newgame-only (New Game + difficulty, never Start): with --timed N the N seconds
# start at New Game and the opening cinematic plays unskipped (movie measurements, PS3_TRACE_VDEC_PIPE=1).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ADB="${ADB:-adb}"
PKG=io.github.andrebrumdev.gow2
EXT="/storage/emulated/0/Android/data/$PKG/files"
OUT="${1:?usage: run_perf.sh OUT_DIR [--seconds N] [--timed N] [--env K=V]... [--simpleperf] [--drive|--drive-newgame] [--p50 N] [--p5 N] [--dry-run]}"
shift
WINDOW_S=200; TIMED=0; SIMPLEPERF=0; DRY=0; DRIVE=0; DRIVE_ARGS=(); P50=30; P5=25; EXTRA_ENV=()
while [ $# -gt 0 ]; do
    case "$1" in
        --seconds) WINDOW_S="$2"; shift 2 ;;
        --timed) TIMED="$2"; shift 2 ;;
        --env) EXTRA_ENV+=("$2"); shift 2 ;;
        --simpleperf) SIMPLEPERF=1; shift ;;
        --drive) DRIVE=1; shift ;;
        --drive-newgame) DRIVE=1; DRIVE_ARGS=(--newgame-only); shift ;;
        --p50) P50="$2"; shift 2 ;;
        --p5) P5="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        *) echo "run_perf.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
mkdir -p "$OUT"

A() { if [ "$DRY" = 1 ]; then echo "DRY adb $*"; else "$ADB" ${ANDROID_SERIAL:+-s "$ANDROID_SERIAL"} "$@" < /dev/null; fi; }
cleanup() {
    A shell "run-as $PKG rm -f files/gow2.override.env" || true
    A shell "am force-stop $PKG" || true
}

if [ "$DRY" != 1 ]; then
    n="$("$ADB" devices | grep -c 'device$' || true)"
    [ "$n" = 1 ] || { echo "run_perf.sh: need exactly one adb device (found $n)" >&2; exit 3; }
    "$ADB" ${ANDROID_SERIAL:+-s "$ANDROID_SERIAL"} shell dumpsys battery < /dev/null | grep -Eq 'AC powered: true|USB powered: true' \
        || { echo "run_perf.sh: the tablet is not on power; thermal and clocks would not be comparable" >&2; exit 3; }
fi

# armed only after the preflight: a refused run must leave the device (and any hand-made override) untouched
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

OV="$(printf '%s\n' PS3_TRACE_FPS=1 PS3_ANDROID_PERF_LOG=1 PS3_PAD_AUTOSTART=1 ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"})"
if [ "$DRY" = 1 ]; then
    echo "DRY override: $(printf '%s' "$OV" | tr '\n' ' ')"
else
    printf '%s\n' "$OV" | "$ADB" ${ANDROID_SERIAL:+-s "$ANDROID_SERIAL"} shell "run-as $PKG sh -c 'cat > files/gow2.override.env'"
fi

A shell "am force-stop $PKG"
A shell "rm -f $EXT/gow2.log"
A shell "am start -n $PKG/.GoW2Activity"

if [ "$DRIVE" = 1 ]; then
    if [ "$DRY" = 1 ]; then
        echo "DRY drive_gameplay${DRIVE_ARGS[*]+ ${DRIVE_ARGS[*]}}"
    else
        bash "$HERE/drive_gameplay.sh" --timeout 600 ${DRIVE_ARGS[@]+"${DRIVE_ARGS[@]}"} || echo "run_perf.sh: drive_gameplay failed (see above); the window will not complete" >&2
    fi
fi

SP="${ANDROID_NDK_ROOT:-/opt/homebrew/share/android-commandlinetools/ndk/27.2.12479018}/simpleperf/bin/android/arm64/simpleperf"
record_simpleperf() {
    A push "$SP" /data/local/tmp/simpleperf
    A shell "chmod 755 /data/local/tmp/simpleperf"
    local pid
    pid="$(A shell "pidof $PKG" | tr -d '\r' | awk '{print $1}' || true)"
    if [ -z "$pid" ]; then echo "run_perf.sh: app not running, skipping simpleperf" >&2; return 0; fi
    A shell "/data/local/tmp/simpleperf record -e cpu-clock -p $pid -g -f 1000 --duration 30 -o /data/local/tmp/gow2.perf.data"
    A shell "/data/local/tmp/simpleperf report -i /data/local/tmp/gow2.perf.data --sort comm -n" > "$OUT/simpleperf_by_thread.txt"
    A shell "/data/local/tmp/simpleperf report -i /data/local/tmp/gow2.perf.data --sort dso,symbol -n --percent-limit 0.5" > "$OUT/simpleperf_by_symbol.txt"
    [ "$DRY" = 1 ] && echo "DRY simpleperf reports -> $OUT/simpleperf_by_thread.txt $OUT/simpleperf_by_symbol.txt" || true
}

if [ "$TIMED" -gt 0 ]; then
    [ "$DRY" = 1 ] && echo "DRY sleep $TIMED" || sleep "$TIMED"
elif [ "$DRY" = 1 ]; then
    echo "DRY wait for $WINDOW_S gameplay seconds"
    [ "$SIMPLEPERF" = 1 ] && { record_simpleperf || echo "run_perf.sh: simpleperf failed, continuing without a profile" >&2; }
else
    have_sp=0; waited=0
    while [ "$waited" -lt $((WINDOW_S + 600)) ]; do
        sleep 10; waited=$((waited + 10))
        cnt="$(A shell "grep -Ec '\[FPS\] fps=[0-9]+ draws=([4-9][0-9]{2}|[0-9]{4,})' $EXT/gow2.log" | tr -d '\r' || true)"
        cnt="${cnt:-0}"
        if [ "$SIMPLEPERF" = 1 ] && [ "$have_sp" = 0 ] && [ "$cnt" -ge 30 ]; then record_simpleperf || echo "run_perf.sh: simpleperf failed, continuing without a profile" >&2; have_sp=1; fi
        [ "$cnt" -ge "$WINDOW_S" ] && break
    done
fi

A shell "cat $EXT/gow2.log" > "$OUT/gow2.log"
if [ "$TIMED" -gt 0 ]; then
    echo "log: $OUT/gow2.log"
elif [ "$DRY" = 1 ]; then
    echo "DRY python3 $HERE/../ios/perf_report.py $OUT/gow2.log --tag ANDPERF --seconds $WINDOW_S --p50 $P50 --p5 $P5 --label android"
else
    rc=0
    python3 "$HERE/../ios/perf_report.py" "$OUT/gow2.log" --tag ANDPERF --seconds "$WINDOW_S" --p50 "$P50" --p5 "$P5" --label android \
        > "$OUT/report.md" || rc=$?
    echo "log: $OUT/gow2.log  report: $OUT/report.md  (perf_report exit $rc: 0 target met, 2 missed/incomplete, 1 no gameplay window)"
fi
