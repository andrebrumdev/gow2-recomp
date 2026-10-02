#!/bin/bash
# run_perf.sh in --dry-run: the exact device commands, the override contents, the cleanup, option errors.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; RP="$HERE/../android/run_perf.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0; bad() { echo "FAIL: $*"; fails=$((fails + 1)); }
PKG=io.github.andrebrumdev.gow2

out="$(bash "$RP" "$T/o" --dry-run --seconds 5 --simpleperf --env PS3_TRACE_VDEC_SESSION=1 2>&1)"; rc=$?
[ "$rc" = 0 ] || bad "dry-run exit $rc: $out"
for want in \
    "DRY adb shell am force-stop $PKG" \
    "DRY adb shell am start -n $PKG/.GoW2Activity" \
    "PS3_TRACE_FPS=1" "PS3_ANDROID_PERF_LOG=1" "PS3_PAD_AUTOSTART=1" "PS3_TRACE_VDEC_SESSION=1" \
    "simpleperf record -e cpu-clock -p" "simpleperf_by_thread.txt" \
    "--tag ANDPERF" "--seconds 5" \
    "run-as $PKG rm -f files/gow2.override.env"; do
    printf '%s\n' "$out" | grep -qF -- "$want" || bad "missing: $want"
done
# the override is removed even on success (trap), and AFTER the app was started
last_rm="$(printf '%s\n' "$out" | grep -n 'gow2.override.env' | tail -1 | cut -d: -f1)"
start="$(printf '%s\n' "$out" | grep -n 'am start' | head -1 | cut -d: -f1)"
[ -n "$last_rm" ] && [ -n "$start" ] && [ "$last_rm" -gt "$start" ] || bad "override cleanup must come after the launch"

# --drive: drive_gameplay runs after the launch and before the gameplay wait; absent without --drive
printf '%s\n' "$out" | grep -q 'drive_gameplay' && bad "drive_gameplay must not appear without --drive"
outd="$(bash "$RP" "$T/d" --dry-run --seconds 5 --drive 2>&1)"; rc=$?
[ "$rc" = 0 ] || bad "dry-run --drive exit $rc: $outd"
l_start="$(printf '%s\n' "$outd" | grep -n 'am start' | head -1 | cut -d: -f1)"
l_drive="$(printf '%s\n' "$outd" | grep -n 'DRY drive_gameplay' | head -1 | cut -d: -f1)"
l_wait="$(printf '%s\n' "$outd" | grep -n 'DRY wait for 5 gameplay seconds' | head -1 | cut -d: -f1)"
[ -n "$l_start" ] && [ -n "$l_drive" ] && [ -n "$l_wait" ] && [ "$l_start" -lt "$l_drive" ] && [ "$l_drive" -lt "$l_wait" ] \
    || bad "--drive order (start < drive < wait) wrong: $outd"

# timed mode: no report, no gameplay polling
out="$(bash "$RP" "$T/t" --dry-run --timed 90 2>&1)"
printf '%s\n' "$out" | grep -q -- "--tag ANDPERF" && bad "timed mode must not run perf_report"
printf '%s\n' "$out" | grep -qF "sleep 90" || bad "timed mode must wait 90 s"

# --drive-newgame + --timed: the drive stops at New Game (no Start), then the timed wait starts
outm="$(bash "$RP" "$T/m" --dry-run --timed 90 --drive-newgame --env PS3_TRACE_VDEC_PIPE=1 2>&1)"; rc=$?
[ "$rc" = 0 ] || bad "dry-run --drive-newgame exit $rc: $outm"
l_drv="$(printf '%s\n' "$outm" | grep -n 'DRY drive_gameplay --newgame-only' | head -1 | cut -d: -f1)"
l_slp="$(printf '%s\n' "$outm" | grep -n 'DRY sleep 90' | head -1 | cut -d: -f1)"
[ -n "$l_drv" ] && [ -n "$l_slp" ] && [ "$l_drv" -lt "$l_slp" ] || bad "--drive-newgame: drive (newgame-only) before the timed wait: $outm"
printf '%s\n' "$outm" | grep -qF "PS3_TRACE_VDEC_PIPE=1" || bad "--drive-newgame: the extra env must reach the override"
printf '%s\n' "$outd" | grep -q -- '--newgame-only' && bad "--drive must not pass --newgame-only"
bash "$RP" "$T/x" --bogus >/dev/null 2>&1; [ "$?" = 2 ] || bad "unknown option must exit 2"
bash "$RP" >/dev/null 2>&1; [ "$?" != 0 ] || bad "missing OUT_DIR must fail"

# ---- real mode against a stub adb (never a real device) ----
STUB="$T/adb_stub.sh"; SLOG="$T/stub.log"
cat > "$STUB" <<'STUBEOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
case "$*" in *'cat > files/'*) cat > /dev/null ;; esac
case "$1" in
    devices)
        echo "List of devices attached"
        i=0; while [ "$i" -lt "${STUB_DEVICES:-1}" ]; do printf 'SER%s\tdevice\n' "$i"; i=$((i + 1)); done ;;
    shell)
        case "${*:2}" in
            "dumpsys battery") [ "${STUB_POWER:-1}" = 1 ] && echo "  USB powered: true" || echo "  USB powered: false" ;;
            *"am start"*) [ "${STUB_START_FAIL:-0}" = 1 ] && exit 1 ;;
        esac ;;
esac
exit 0
STUBEOF
chmod +x "$STUB"
unset ANDROID_SERIAL
run_stub() { : > "$SLOG"; STUB_LOG="$SLOG" ADB="$STUB" bash "$RP" "$T/s" "$@" >/dev/null 2>&1; }
untouched() { # $1 = label
    grep -q 'force-stop' "$SLOG" && bad "$1: preflight failure must not force-stop"
    grep -q 'rm -f files/gow2.override.env' "$SLOG" && bad "$1: preflight failure must not rm the override"
    grep -q 'am start' "$SLOG" && bad "$1: must not launch"
    return 0
}
STUB_DEVICES=2 run_stub --timed 1; rc=$?
[ "$rc" = 3 ] || bad "two devices: exit $rc, want 3"; untouched "two devices"
STUB_DEVICES=1 STUB_POWER=0 run_stub --timed 1; rc=$?
[ "$rc" = 3 ] || bad "no power: exit $rc, want 3"; untouched "no power"

STUB_DEVICES=1 STUB_POWER=1 run_stub --timed 1; rc=$?
[ "$rc" = 0 ] || bad "timed real run: exit $rc, want 0"
grep -q "run-as $PKG sh -c 'cat > files/gow2.override.env'" "$SLOG" || bad "timed real run: override not written"
st="$(grep -n 'am start' "$SLOG" | head -1 | cut -d: -f1)"
rm_l="$(grep -n 'rm -f files/gow2.override.env' "$SLOG" | tail -1 | cut -d: -f1)"
fs_l="$(grep -n 'force-stop' "$SLOG" | tail -1 | cut -d: -f1)"
[ -n "$st" ] && [ -n "$rm_l" ] && [ -n "$fs_l" ] && [ "$rm_l" -gt "$st" ] && [ "$fs_l" -gt "$st" ] || bad "timed real run: cleanup must follow launch"

STUB_DEVICES=1 STUB_POWER=1 STUB_START_FAIL=1 run_stub --timed 1; rc=$?
[ "$rc" != 0 ] || bad "failing am start must fail the script"
grep -q 'rm -f files/gow2.override.env' "$SLOG" || bad "abort: trap must rm the override"
grep -q 'force-stop' "$SLOG" || bad "abort: trap must force-stop"

[ "$fails" = 0 ] && { echo "test_android_run_perf: PASS"; exit 0; }
echo "test_android_run_perf: FAIL ($fails)"; exit 1
