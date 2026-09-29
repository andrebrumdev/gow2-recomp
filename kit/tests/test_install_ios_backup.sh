#!/usr/bin/env bash
# ios/install_ios.sh never installs without a copy of the phone's saves: its own verified
# backup, or a backup folder the caller just wrote that the script can verify itself
# against the phone's own listing (GOW2_IOS_SAVES_BACKUP_DIR: exactly the phone's savedata
# files and sizes, no symlinks, sha256.txt checks, fresh backup.meta, same bundle and device). No env
# flag alone skips it (Codex review BLOCKER, 2026-09-28). Nothing in the iOS scripts or the
# launcher asks devicectl to delete destination content (it once wiped the app's Documents).
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
        [ "${FAKE_FILES_RC:-0}" = 0 ] || exit 1
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
    env -u GOW2_WORK -u GOW2_IOS_SAVES_BACKED_UP -u GOW2_IOS_SAVES_BACKUP_DIR PATH="$T/bin:/usr/bin:/bin" FAKE_LOG="$log" \
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
t_true "and a backup.meta naming the bundle" grep -qx 'bundle=com.abcde12345.gow2recomp' "$BK/backup.meta"
t_true "... and the device" grep -qx 'udid=00008110-TEST' "$BK/backup.meta"

rm -rf "$T/bk"; run "$T/fail.log" FAKE_FROM_RC=1; t_eq 1 $? "backup failed -> rc 1"
t_false "backup failed -> no app install" grep -q 'install app' "$T/fail.log"
t_eq "" "$(ls -A "$T/bk" 2>/dev/null)" "backup failed -> no empty backup folder left"
t_false "and never offers an env flag to skip the backup" grep -q 'GOW2_IOS_SAVES_BACKED_UP' "$T/fail.log.out"

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
# Codex re-review CRITICAL (Task 7): devicectl can exit 0 and still write a failed outcome;
# an empty array under a failed outcome is not "not installed" / "no save".
run "$T/appsfailed0.log" FAKE_APPS_JSON='{"info":{"outcome":"failed"},"result":{"apps":[]}}'; t_eq 1 $? "app list outcome failed + [] -> rc 1"
t_false "app list outcome failed -> no app install" grep -q 'install app' "$T/appsfailed0.log"
run "$T/filesfailed0.log" FAKE_LISTING_JSON='{"info":{"outcome":"failed"},"result":{"files":[]}}'; t_eq 1 $? "file listing outcome failed + [] -> rc 1"
t_false "file listing outcome failed -> no app install" grep -q 'install app' "$T/filesfailed0.log"
t_true "reinstall -> apps listed before the files" test "$(line_of 'info apps' "$T/ok.log")" -lt "$(line_of 'info files' "$T/ok.log")"

# Codex review BLOCKER, 2026-09-28: the old flag alone no longer skips the backup.
rm -rf "$T/bk"
run "$T/legacy.log" GOW2_IOS_SAVES_BACKED_UP=1; t_eq 0 $? "legacy flag -> still installs"
t_true "legacy flag -> the script lists the phone itself" grep -q 'info files' "$T/legacy.log"
t_true "legacy flag -> and copies the saves itself" grep -q 'copy from' "$T/legacy.log"
t_true "legacy flag -> copy before the app install" \
    test "$(line_of 'copy from' "$T/legacy.log")" -lt "$(line_of 'install app' "$T/legacy.log")"

# The launcher's handshake: GOW2_IOS_SAVES_BACKUP_DIR = the folder it just wrote. It stands
# for this run's backup only if it is the PHONE's saves (Codex re-review, 2026-09-28): the
# script still lists the phone and checks the folder against that listing -- same relative
# paths and sizes, nothing extra, no symlinks -- plus sha256.txt, backup.meta and a fresh
# backup.meta (the launcher writes it last; the folder's own mtime proves nothing).
mk_bk() { # mk_bk <dir> [bundle] [udid]: a backup folder like the launcher writes
    rm -rf "$1"; mkdir -p "$1/BCUS98229_GOW2"
    echo save > "$1/BCUS98229_GOW2/SYS.BIN"
    ( cd "$1" && shasum -a 256 BCUS98229_GOW2/SYS.BIN > sha256.txt )
    printf 'bundle=%s\nudid=%s\n' "${2:-com.abcde12345.gow2recomp}" "${3:-00008110-TEST}" > "$1/backup.meta"
}
resha() { ( cd "$1" && find -L . -type f ! -path ./sha256.txt ! -path ./backup.meta | sed 's|^\./||' | sort \
             | while IFS= read -r f; do shasum -a 256 "$f"; done > sha256.txt ); touch "$1/backup.meta"; }
entry() { printf '{"relativePath":"savedata/%s","metadata":{"size":%s},"resources":{"isDirectory":false}}' "$1" "$2"; }
listing() { local IFS=,; printf '{"info":{"outcome":"success"},"result":{"files":[%s]}}' "$*"; }
DIRE='{"relativePath":"savedata/BCUS98229_GOW2","resources":{"isDirectory":true}}'
V="$T/handshake"
mk_bk "$V"; rm -rf "$T/bk"
run "$T/hs_ok.log" GOW2_IOS_SAVES_BACKUP_DIR="$V" FAKE_LISTING_JSON="$(listing "$DIRE" "$(entry BCUS98229_GOW2/SYS.BIN 5)")"
t_eq 0 $? "valid handshake -> installs"
t_true "valid handshake -> the phone is still listed (to check the folder against)" grep -q 'info files' "$T/hs_ok.log"
t_false "valid handshake -> no second copy from the phone" grep -q 'copy from' "$T/hs_ok.log"
t_true "valid handshake -> app installed" grep -q 'install app' "$T/hs_ok.log"
t_true "valid handshake -> says which backup it trusted" grep -q "$V" "$T/hs_ok.log.out"
t_false "valid handshake -> not rejected" grep -q 'not accepted' "$T/hs_ok.log.out"
t_eq "" "$(ls -A "$T/bk" 2>/dev/null)" "valid handshake -> no own backup folder"
t_true "valid handshake -> the app list is still read (first install is decided by the phone)" \
    grep -q 'info apps' "$T/hs_ok.log"
OUTSIDE="$T/outside"
for c in missing nosha tampered old staledirtouched otherbundle otherudid nometa emptysha \
         arbitrary symlink symlinkfile missingphone sizemismatch extra emptybackup shapartial; do
    mk_bk "$V"; LJ_CASE=""
    case $c in
        missing)     rm -rf "$V" ;;
        nosha)       rm -f "$V/sha256.txt" ;;
        tampered)    echo forged > "$V/BCUS98229_GOW2/SYS.BIN" ;;
        old)         touch -t 202001010000 "$V/backup.meta" "$V" ;;
        staledirtouched) touch -t 202001010000 "$V/backup.meta"; touch "$V" ;;
        otherbundle) mk_bk "$V" com.other.app ;;
        otherudid)   mk_bk "$V" com.abcde12345.gow2recomp 00008110-OTHER ;;
        nometa)      rm -f "$V/backup.meta" ;;
        emptysha)    : > "$V/sha256.txt" ;;
        arbitrary)   # any file with a matching checksum and meta is not the phone's save
                     rm -rf "$V/BCUS98229_GOW2"; mkdir -p "$V/X"; echo evil > "$V/X/ANY.BIN"; resha "$V" ;;
        symlink)     # the save folder is a link to somewhere else on the Mac
                     rm -rf "$OUTSIDE"; mkdir -p "$OUTSIDE"; mv "$V/BCUS98229_GOW2" "$OUTSIDE/"
                     ln -s "$OUTSIDE/BCUS98229_GOW2" "$V/BCUS98229_GOW2"; resha "$V" ;;
        symlinkfile) rm -rf "$OUTSIDE"; mkdir -p "$OUTSIDE"; mv "$V/BCUS98229_GOW2/SYS.BIN" "$OUTSIDE/SYS.BIN"
                     ln -s "$OUTSIDE/SYS.BIN" "$V/BCUS98229_GOW2/SYS.BIN"; touch "$V/backup.meta" ;;
        missingphone) LJ_CASE="$(listing "$(entry BCUS98229_GOW2/SYS.BIN 5)" "$(entry BCUS98229_GOW2/ICON0.PNG 5)")" ;;
        sizemismatch) printf 'saved\n' > "$V/BCUS98229_GOW2/SYS.BIN"; resha "$V" ;;   # 6 bytes, phone says 5
        extra)       echo more > "$V/BCUS98229_GOW2/EXTRA.BIN"; resha "$V" ;;
        emptybackup) rm -rf "$V/BCUS98229_GOW2"; : > "$V/sha256.txt"; touch "$V/backup.meta" ;;
        shapartial)  # the folder has both phone files, sha256.txt vouches for only one
                     echo icon > "$V/BCUS98229_GOW2/ICON0.PNG"; touch "$V/backup.meta"
                     LJ_CASE="$(listing "$(entry BCUS98229_GOW2/SYS.BIN 5)" "$(entry BCUS98229_GOW2/ICON0.PNG 5)")" ;;
    esac
    rm -rf "$T/bk"
    if [ -n "$LJ_CASE" ]; then
        # The phone lists two saves: the script's own copy (the fake copies SYS.BIN only)
        # then fails the listing check too -> nothing installed.
        run "$T/hs_$c.log" GOW2_IOS_SAVES_BACKUP_DIR="$V" FAKE_LISTING_JSON="$LJ_CASE"
        t_eq 1 $? "forged handshake ($c) -> own backup cannot match either -> rc 1"
        t_true "forged handshake ($c) -> rejected, says so" grep -q 'not accepted' "$T/hs_$c.log.out"
        t_false "forged handshake ($c) -> no app install" grep -q 'install app' "$T/hs_$c.log"
        continue
    fi
    run "$T/hs_$c.log" GOW2_IOS_SAVES_BACKUP_DIR="$V"; t_eq 0 $? "forged handshake ($c) -> still installs"
    t_true "forged handshake ($c) -> rejected, says so" grep -q 'not accepted' "$T/hs_$c.log.out"
    t_true "forged handshake ($c) -> own listing + copy" grep -q 'copy from' "$T/hs_$c.log"
    t_true "forged handshake ($c) -> own copy before the app install" \
        test "$(line_of 'copy from' "$T/hs_$c.log")" -lt "$(line_of 'install app' "$T/hs_$c.log")"
done
grep -h 'not accepted' "$T"/hs_*.log.out | sed 's/^/       /'
# A forged handshake whose own backup then fails: nothing installed.
mk_bk "$V"; rm -f "$V/sha256.txt"; rm -rf "$T/bk"
run "$T/hs_fail.log" GOW2_IOS_SAVES_BACKUP_DIR="$V" FAKE_FROM_RC=1; t_eq 1 $? "forged handshake + failed own backup -> rc 1"
t_false "forged handshake + failed own backup -> no app install" grep -q 'install app' "$T/hs_fail.log"
# A valid handshake is never enough on its own: the phone listing must succeed.
mk_bk "$V"; rm -rf "$T/bk"
run "$T/hs_listfail.log" GOW2_IOS_SAVES_BACKUP_DIR="$V" FAKE_FILES_RC=1; t_eq 1 $? "handshake + listing fails -> rc 1"
t_false "handshake + listing fails -> no app install" grep -q 'install app' "$T/hs_listfail.log"
mk_bk "$V"
run "$T/hs_listbad.log" GOW2_IOS_SAVES_BACKUP_DIR="$V" FAKE_LISTING_JSON='{"info":{"outcome":"failed"},"result":{"files":[]}}'
t_eq 1 $? "handshake + listing outcome failed -> rc 1"
t_false "handshake + listing outcome failed -> no app install" grep -q 'install app' "$T/hs_listbad.log"
# App on the phone, successful listing with no savedata: nothing to back up, installs.
rm -rf "$T/bk"
run "$T/nosave.log" FAKE_LISTING_JSON='{"info":{"outcome":"success"},"result":{"files":[{"relativePath":"EBOOT.ELF","metadata":{"size":1},"resources":{"isDirectory":false}}]}}'
t_eq 0 $? "app present, no savedata listed -> installs"
t_false "no savedata -> no copy from" grep -q 'copy from' "$T/nosave.log"
t_true "no savedata -> says so" grep -q 'no Documents/savedata' "$T/nosave.log.out"

# Static bans over the scripts and the launcher sources.
t_eq "" "$(grep -l -- 'remove-existing-content' "$R"/ios/*.sh "$R"/launcher/macos/*.swift 2>/dev/null)" \
    "no ios script or launcher source mentions remove-existing-content"
t_eq "" "$(grep -l -- 'GOW2_IOS_SAVES_BACKED_UP' "$R"/ios/*.sh "$R"/launcher/macos/*.swift "$R"/launcher/macos/tests/ios_check/*.swift 2>/dev/null)" \
    "no script or launcher source still knows the old skip flag"
t_done
