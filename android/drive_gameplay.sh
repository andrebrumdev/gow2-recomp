#!/bin/bash
# drive_gameplay.sh [--timeout S] [--newgame-only] [--dry-run] -- from the home screen to the first gameplay second on the tablet, with the
# virtual touch controls (real touches through `adb shell input`). Launches nothing (run_perf.sh did), never touches the
# savedata and never runs pm/am. Stops with a reason instead of spinning: exit 0 "gameplay"; exit 1 "no-menu",
# "no-gameplay" or "app-died". Coordinates are for the 2560x1600 landscape frame. DRIVE_POLL (default 5 s) is the poll step.
# --newgame-only: stop right after New Game + difficulty (exit 0 "newgame") and never press Start, so the opening
# cinematic plays (movie measurements: run_perf.sh --drive-newgame --timed N).
set -uo pipefail
ADB="${ADB:-adb}"
PKG=io.github.andrebrumdev.gow2
EXT="/storage/emulated/0/Android/data/$PKG/files"
TIMEOUT=600; DRY=0; NEWGAME_ONLY=0; POLL="${DRIVE_POLL:-5}"
while [ $# -gt 0 ]; do
    case "$1" in
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        --newgame-only) NEWGAME_ONLY=1; shift ;;
        *) echo "drive_gameplay.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
A() { if [ "$DRY" = 1 ]; then echo "DRY adb $*"; else "$ADB" ${ANDROID_SERIAL:+-s "$ANDROID_SERIAL"} "$@" < /dev/null; fi; }
press() { A shell "input swipe $1 $2 $1 $2 600"; }       # a 600 ms hold: the guest samples the pad once per frame and cinematics run at 5-6 fps (300 ms missed Start, 2026-10-01)
alive() { [ -n "$(A shell "pidof $PKG" | tr -d '\r')" ]; }
log_has() { A shell "grep -Eq '$1' $EXT/gow2.log" > /dev/null 2>&1; }
menu() { log_has 'st620 [0-9]+ -> 0 ' && log_has '\[FPS\] fps=[0-9]+ draws=2[0-9][0-9] '; }
gameplay() { log_has '\[FPS\] fps=[0-9]+ draws=([4-9][0-9]{2}|[0-9]{4,})'; }
fail() { echo "drive_gameplay: $1"; exit 1; }
start=$(date +%s)
left() { [ $(( $(date +%s) - start )) -lt "$TIMEOUT" ]; }

if [ "$DRY" = 1 ]; then
    press 550 830                                        # Jogar
    echo "DRY wait for the main menu"
    press 2235 1084                                      # Cross: New Game
    press 2235 1084                                      # Cross: the default difficulty
    [ "$NEWGAME_ONLY" = 1 ] && { echo "DRY stop after New Game: the cinematic plays"; exit 0; }
    press 1518 96                                        # Start: skips the opening cinematic
    echo "DRY wait for gameplay"
    exit 0
fi

until log_has 'home screen up'; do                       # a tap before the home screen is up is lost (seen 2026-09-30)
    alive || fail "app-died"
    left || fail "no-home"
    sleep 1
done
sleep 3
press 550 830                                            # Jogar
echo "drive_gameplay: tapped Jogar"
until menu; do
    alive || fail "app-died"
    left || fail "no-menu"
    sleep "$POLL"
done
press 2235 1084                                          # Cross: New Game (focus starts there)
echo "drive_gameplay: pressed New Game"
sleep "$POLL"
press 2235 1084                                          # Cross: the default difficulty
[ "$NEWGAME_ONLY" = 1 ] && { echo "drive_gameplay: newgame"; exit 0; }   # the cinematic plays; nothing skips it
while :; do
    gameplay && { echo "drive_gameplay: gameplay"; exit 0; }
    alive || fail "app-died"
    left || fail "no-gameplay"
    press 1518 96                                        # Start: skips the opening cinematic
    sleep "$POLL"
done
