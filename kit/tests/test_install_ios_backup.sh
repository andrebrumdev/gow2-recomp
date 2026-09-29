#!/usr/bin/env bash
# ios/install_ios.sh never installs without a copy of the phone's saves, and nothing in
# the iOS scripts or the launcher passes --remove-existing-content outside the F6 guard.
# Fake xcrun; no device.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/g/ios" "$T/ps3recomp" "$T/bin" "$T/g/build-ios/dd/Build/Products/Release-iphoneos/GoW2.app"
cp "$R/ios/install_ios.sh" "$R/ios/ios_env.sh" "$T/g/ios/"
: > "$T/ps3recomp/CMakeLists.txt"
cat > "$T/bin/xcrun" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
j=""; d=""; b=""; prev=""
for a in "$@"; do
    [ "$prev" = -j ] && j="$a"
    [ "$prev" = --destination ] && d="$a"
    [ "$prev" = --bundle-id ] && b="$a"
    prev="$a"
done
case "$*" in
    *"info apps"*)
        # Is the bundle on the phone already? Default: yes (a reinstall).
        [ "${FAKE_APPS_RC:-0}" = 0 ] || exit 1
        [ -n "$j" ] || exit 1
        defa="{\"info\":{\"outcome\":\"success\"},\"result\":{\"apps\":[{\"bundleIdentifier\":\"$b\",\"name\":\"GoW2\"}]}}"
        printf '%s\n' "${FAKE_APPS_JSON:-$defa}" > "$j"
        ;;
    *"info files"*)
        # The phone-side listing install_ios.sh verifies its copy against (Codex review
        # MAJOR, 2026-09-28); default matches what the "copy from" case below produces.
        # (The default sits in its own variable: a "{...}" default inside ${VAR:-...}
        # is cut at its first "}" and loses its quotes.)
        [ -n "$j" ] || exit 1
        def='{"info":{"outcome":"success"},"result":{"files":[{"relativePath":"savedata/BCUS98229_GOW2/SYS.BIN","metadata":{"size":5},"resources":{"isDirectory":false}}]}}'
        printf '%s\n' "${FAKE_LISTING_JSON:-$def}" > "$j"
        ;;
    *"copy from"*)
        [ "${FAKE_FROM_RC:-0}" = 0 ] || exit 1
        mkdir -p "$d/BCUS98229_GOW2" && echo save > "$d/BCUS98229_GOW2/SYS.BIN" ;;
esac
exit 0
EOF
chmod +x "$T/bin/xcrun"
run() { # run <log> [VAR=value...]
    local log=$1; shift
    env -u GOW2_WORK -u GOW2_IOS_SAVES_BACKED_UP PATH="$T/bin:/usr/bin:/bin" FAKE_LOG="$log" \
        GOW2_IOS_DEVICE=00008110-TEST GOW2_IOS_TEAM=ABCDE12345 GOW2_IOS_SAVE_BACKUP_DIR="$T/bk" \
        "$@" /bin/bash "$T/g/ios/install_ios.sh" > "$log.out" 2>&1
}
line_of() { grep -n -- "$1" "$2" | head -1 | cut -d: -f1; }

run "$T/ok.log"; t_eq 0 $? "backup ok -> install ok"
t_true "install ok marker" grep -q GOW2_IOS_INSTALL_OK "$T/ok.log.out"
t_true "the phone was listed first (Codex review MAJOR: an independent source to verify against)" \
    grep -q -- '--subdirectory Documents -t 120 -j' "$T/ok.log"
t_true "the saves were copied from the phone" grep -q 'device copy from .*--source Documents/savedata' "$T/ok.log"
t_true "... listing before copy" test "$(line_of 'info files' "$T/ok.log")" -lt "$(line_of 'copy from' "$T/ok.log")"
t_true "... copy before the app install" test "$(line_of 'copy from' "$T/ok.log")" -lt "$(line_of 'install app' "$T/ok.log")"
BK="$(ls -d "$T"/bk/*-iphone-cli 2>/dev/null | head -1)"
t_true "backup folder holds the save" test -f "$BK/BCUS98229_GOW2/SYS.BIN"
t_true "with its sha256 list" grep -q 'BCUS98229_GOW2/SYS.BIN' "$BK/sha256.txt"

rm -rf "$T/bk"; run "$T/fail.log" FAKE_FROM_RC=1; t_eq 1 $? "backup failed -> rc 1"
t_false "backup failed -> no app install" grep -q 'install app' "$T/fail.log"
t_eq "" "$(ls -A "$T/bk" 2>/dev/null)" "backup failed -> no empty backup folder left"
t_true "and says how to go on" grep -q 'GOW2_IOS_SAVES_BACKED_UP=1' "$T/fail.log.out"

# Codex review MAJOR, 2026-09-28: a "copy from" that exits 0 but does not actually match
# what the phone listed (here: the phone says the file is 999 bytes) must refuse the
# install too -- sha256.txt of whatever landed locally would not have caught this.
rm -rf "$T/bk"
run "$T/mismatch.log" FAKE_LISTING_JSON='{"info":{"outcome":"success"},"result":{"files":[{"relativePath":"savedata/BCUS98229_GOW2/SYS.BIN","metadata":{"size":999},"resources":{"isDirectory":false}}]}}'
t_eq 1 $? "phone listing mismatches the copy -> rc 1"
t_false "mismatch -> no app install" grep -q 'install app' "$T/mismatch.log"
t_true "mismatch -> says why" grep -qE "phone's listing|verification" "$T/mismatch.log.out"
t_eq "" "$(ls -A "$T/bk" 2>/dev/null)" "mismatch -> no half backup folder left"

# Codex review CRITICAL (Task 7): an entry the listing cannot describe (no relativePath,
# no size) used to end the scan early -- saves listed after it were never backed up and
# the install went on. Any unreadable entry now refuses the install.
for c in nopath nosize; do
    rm -rf "$T/bk"
    case $c in
        nopath) bad='{"metadata":{"size":1},"resources":{"isDirectory":false}}' ;;
        nosize) bad='{"relativePath":"savedata/BCUS98229_GOW2/ICON0.PNG","resources":{"isDirectory":false}}' ;;
    esac
    run "$T/$c.log" FAKE_LISTING_JSON="{\"info\":{\"outcome\":\"success\"},\"result\":{\"files\":[$bad,{\"relativePath\":\"savedata/BCUS98229_GOW2/SYS.BIN\",\"metadata\":{\"size\":5},\"resources\":{\"isDirectory\":false}}]}}"
    t_eq 1 $? "$c entry in the phone listing -> rc 1"
    t_false "$c entry -> no app install" grep -q 'install app' "$T/$c.log"
    t_true "$c entry -> says why" grep -q 'unreadable entry' "$T/$c.log.out"
done

# Codex review IMPORTANT (Task 7): first install of a bundle (the phone's own app list does
# not have it) needs no backup and no override; a failed app listing is still a refusal.
rm -rf "$T/bk"
run "$T/first.log" FAKE_APPS_JSON='{"info":{"outcome":"success"},"result":{"apps":[]}}'; t_eq 0 $? "first install -> installs"
t_true "first install -> the app list was asked with the bundle id" grep -q 'info apps .*--bundle-id com.abcde12345.gow2recomp' "$T/first.log"
t_false "first install -> no file listing, no copy from" grep -qE 'info files|copy from' "$T/first.log"
t_true "first install -> says so" grep -q 'not on the phone yet' "$T/first.log.out"
t_true "first install -> app installed" grep -q 'install app' "$T/first.log"
run "$T/appsfail.log" FAKE_APPS_RC=1; t_eq 1 $? "app list fails -> rc 1"
t_false "app list fails -> no app install" grep -q 'install app' "$T/appsfail.log"
run "$T/appsbad.log" FAKE_APPS_JSON='{"info":{"outcome":"failed"}}'; t_eq 1 $? "app list without result.apps -> rc 1"
t_false "app list without result.apps -> no app install" grep -q 'install app' "$T/appsbad.log"
t_true "reinstall -> apps listed before the files" test "$(line_of 'info apps' "$T/ok.log")" -lt "$(line_of 'info files' "$T/ok.log")"

run "$T/skip.log" GOW2_IOS_SAVES_BACKED_UP=1; t_eq 0 $? "caller already backed up -> install"
t_false "caller already backed up -> no listing, no copy from" grep -qE 'info apps|info files|copy from' "$T/skip.log"

t_false "no --remove-existing-content reaches devicectl" grep -q -- '--remove-existing-content' "$T/ok.log" "$T/skip.log"
t_eq "" "$(grep -l -- '--remove-existing-content' "$R"/ios/*.sh 2>/dev/null)" "no ios script passes --remove-existing-content"
t_eq "IOSDevicectl.swift IOSModels.swift" "$(cd "$R/launcher/macos" && grep -l -- '--remove-existing-content' *.swift | tr '\n' ' ' | sed 's/ $//')" \
    "only the F6-guarded transport (and a comment in IOSModels) mention it"
t_done
