#!/bin/bash
# drive_gameplay.sh: dry-run order of the taps, and the exit code + printed reason against a stub adb (never a device).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; DG="$HERE/../android/drive_gameplay.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0; bad() { echo "FAIL: $*"; fails=$((fails + 1)); }
PKG=io.github.andrebrumdev.gow2
EXT="/storage/emulated/0/Android/data/$PKG/files"

# ---- dry run: the ordered sequence ----
out="$(bash "$DG" --dry-run 2>&1)"; rc=$?
[ "$rc" = 0 ] || bad "dry-run exit $rc: $out"
l_jogar="$(printf '%s\n' "$out" | grep -n 'input swipe 550 830 550 830' | head -1 | cut -d: -f1)"
l_menu="$(printf '%s\n' "$out" | grep -n 'DRY wait for the main menu' | head -1 | cut -d: -f1)"
l_cross="$(printf '%s\n' "$out" | grep -n 'input swipe 2235 1084 2235 1084' | head -1 | cut -d: -f1)"
l_start="$(printf '%s\n' "$out" | grep -n 'input swipe 1518 96 1518 96' | head -1 | cut -d: -f1)"
for v in "$l_jogar" "$l_menu" "$l_cross" "$l_start"; do [ -n "$v" ] || bad "dry-run missing a step: $out"; done
if [ -n "$l_jogar" ] && [ -n "$l_menu" ] && [ -n "$l_cross" ] && [ -n "$l_start" ]; then
    [ "$l_jogar" -lt "$l_menu" ] && [ "$l_menu" -lt "$l_cross" ] && [ "$l_cross" -lt "$l_start" ] || bad "dry-run order wrong: $out"
fi
bash "$DG" --bogus >/dev/null 2>&1; [ "$?" = 2 ] || bad "unknown option must exit 2"
# --newgame-only: New Game and the difficulty, then stop -- Start (which skips the cinematic) never pressed
outn="$(bash "$DG" --dry-run --newgame-only 2>&1)"; rc=$?
[ "$rc" = 0 ] || bad "dry-run --newgame-only exit $rc: $outn"
[ "$(printf '%s\n' "$outn" | grep -c 'input swipe 2235 1084 2235 1084')" = 2 ] || bad "--newgame-only: New Game + difficulty: $outn"
printf '%s\n' "$outn" | grep -q 'input swipe 1518 96' && bad "--newgame-only must not press Start: $outn"

# ---- stub adb: `shell grep` runs against a fake log file, `pidof` is scripted ----
STUB="$T/adb_stub.sh"; SLOG="$T/stub.log"; FAKE="$T/fake.log"
cat > "$STUB" <<'STUBEOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1" = shell ] || exit 0
cmd="${*:2}"
case "$cmd" in
    pidof*) [ "${STUB_ALIVE:-1}" = 1 ] && echo 4242; exit 0 ;;
    grep*) cmd="$(printf '%s' "$cmd" | sed "s#$STUB_EXT/gow2.log#$STUB_FAKE#")"; bash -c "$cmd"; exit $? ;;
esac
exit 0
STUBEOF
chmod +x "$STUB"
unset ANDROID_SERIAL
run() { : > "$SLOG"; STUB_LOG="$SLOG" STUB_EXT="$EXT" STUB_FAKE="$FAKE" DRIVE_POLL=1 ADB="$STUB" bash "$DG" "$@" 2>&1; }
nosave() { # $1 label
    grep -q 'savedata' "$SLOG" && bad "$1: must not touch savedata"
    grep -Eq '(^| )pm ' "$SLOG" && bad "$1: must not run pm"
    grep -Eq 'shell am ' "$SLOG" && bad "$1: must not run am"
    return 0
}

HOME="[android] home screen up (game data present)"

# no home line: never presses anything past the home
: > "$FAKE"
o="$(run --timeout 3)"; rc=$?
[ "$rc" != 0 ] && printf '%s\n' "$o" | grep -q 'no-home' || bad "no home: rc=$rc out=$o"; nosave "no-home"
grep -Eq 'input swipe (550 830|2235 1084|1518 96)' "$SLOG" && bad "no home: must not tap anything"

printf '%s\n' "$HOME" > "$FAKE"
o="$(run --timeout 7)"; rc=$?
[ "$rc" != 0 ] && printf '%s\n' "$o" | grep -q 'no-menu' || bad "no menu: rc=$rc out=$o"; nosave "no-menu"
grep -q 'input swipe 550 830' "$SLOG" || bad "no menu: Jogar not tapped"

printf '%s\n' "$HOME" "st620 3 -> 0 " "[FPS] fps=30 draws=228 " > "$FAKE"
o="$(run --timeout 7)"; rc=$?   # menu reached, gameplay never
[ "$rc" != 0 ] && printf '%s\n' "$o" | grep -q 'no-gameplay' || bad "no gameplay: rc=$rc out=$o"; nosave "no-gameplay"
grep -q 'input swipe 2235 1084' "$SLOG" || bad "no gameplay: Cross not pressed"
grep -q 'input swipe 1518 96' "$SLOG" || bad "no gameplay: Start not pressed"

printf '%s\n' "$HOME" "st620 3 -> 0 " "[FPS] fps=30 draws=228 " "[FPS] fps=30 draws=600" > "$FAKE"
o="$(run --timeout 30)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$o" | grep -q 'gameplay' || bad "gameplay: rc=$rc out=$o"; nosave "gameplay"

# --newgame-only against the stub: the menu is reached, New Game + difficulty pressed, exit 0 "newgame", no Start
printf '%s\n' "$HOME" "st620 3 -> 0 " "[FPS] fps=30 draws=228 " > "$FAKE"
o="$(run --timeout 30 --newgame-only)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$o" | grep -q 'drive_gameplay: newgame' || bad "newgame-only: rc=$rc out=$o"; nosave "newgame-only"
[ "$(grep -c 'input swipe 2235 1084' "$SLOG")" = 2 ] || bad "newgame-only: Cross must be pressed twice"
grep -q 'input swipe 1518 96' "$SLOG" && bad "newgame-only: Start must never be pressed"

: > "$FAKE"
o="$(STUB_ALIVE=0 run --timeout 30)"; rc=$?
[ "$rc" != 0 ] && printf '%s\n' "$o" | grep -q 'app-died' || bad "app died: rc=$rc out=$o"; nosave "app-died"

printf '%s\n' "$HOME" "st620 3 -> 0 " "[FPS] fps=30 draws=228 " > "$FAKE"
o="$(STUB_ALIVE=0 run --timeout 30)"; rc=$?
[ "$rc" != 0 ] && printf '%s\n' "$o" | grep -q 'app-died' || bad "app died after menu: rc=$rc out=$o"

[ "$fails" = 0 ] && { echo "test_android_drive_gameplay: PASS"; exit 0; }
echo "test_android_drive_gameplay: FAIL ($fails)"; exit 1
