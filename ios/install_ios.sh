#!/bin/bash
# install_ios.sh [--data] -- installs the built GoW2.app on the device (a
# reinstall = re-sign: the app's data container is kept). --data also copies
# EBOOT.ELF, USRDIR and movie_cache into the container's Documents (first
# install; devicectl skips files that did not change), after overwriting
# Documents/gow2-install.manifest with the incomplete marker. Final line
# "GOW2_IOS_INSTALL_OK" on success.
# Before the app is (re)installed the phone's saves are copied to the Mac
# (${GOW2_IOS_SAVE_BACKUP_DIR:-~/Documents/GoW2 Saves}/<stamp>-iphone-cli) and verified
# against an INDEPENDENT phone-side file listing taken before the copy (Codex review
# MAJOR, 2026-09-28: a sha256.txt of whatever happened to land locally is not a
# verification -- it cannot tell a full copy from a "copy from" that silently stopped
# half-way and still exited 0); if the listing, the copy, or that verification fails,
# nothing is installed. A bundle the phone's app list does not have (first install) has
# nothing to keep and skips it -- decided here from the phone's own app list, never from
# the environment.
# The Mac launcher backs the saves up itself right before calling this script and passes
# GOW2_IOS_SAVES_BACKUP_DIR=<the folder it just wrote>. That folder replaces this script's
# own copy only if the script can verify it (Codex review BLOCKER, 2026-09-28: a bare
# "already backed up" env flag let anyone skip the backup) AND verify that it holds the
# PHONE's saves (Codex re-review, 2026-09-28: a recent folder with any file, a matching
# checksum and a matching meta used to pass). So the phone is always listed when the app
# is on it, and the folder must: hold no symlink anywhere; hold every file the phone lists
# under Documents/savedata at the same relative path and size, and nothing else besides
# sha256.txt and backup.meta; have a sha256.txt that covers exactly those files and checks
# (shasum -c, relative paths only); have a backup.meta naming this bundle and device and
# written in the last 15 minutes (the launcher writes it last; the folder's own mtime
# proves nothing). Anything else is reported and the script makes its own verified backup
# (or installs nothing).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/ios_env.sh"
[ -n "$DEV" ] || { echo "set GOW2_IOS_DEVICE in local.env" >&2; exit 1; }
[ -d "$APP" ] || { echo "no app at $APP: run build_ios.sh" >&2; exit 1; }
# Why GOW2_IOS_SAVES_BACKUP_DIR cannot stand for this run's backup (empty = it can).
# Checked against $LISTING, the phone's own "<relpath under savedata/>\t<size>" rows.
handshake_problem() {
    local d="$1" now m age rel size f got n
    [ -d "$d" ] && [ ! -L "$d" ] || { echo "not a folder"; return; }
    # No symlink anywhere inside: a link can point the checked paths outside the folder.
    [ -z "$(find "$d" -type l 2>/dev/null | head -1)" ] || { echo "it holds a symlink"; return; }
    [ -f "$d/backup.meta" ] || { echo "no backup.meta"; return; }
    # Freshness of backup.meta, which the launcher writes last (not the folder's mtime).
    now="$(date +%s)"
    m="$( { stat -f %m "$d/backup.meta" 2>/dev/null || stat -c %Y "$d/backup.meta" 2>/dev/null; } || true )"
    case "$m" in ''|*[!0-9]*) echo "unreadable backup.meta mtime"; return ;; esac
    age=$((now - m))
    { [ "$age" -ge -60 ] && [ "$age" -lt 900 ]; } || { echo "backup.meta written ${age}s ago, not in the last 15 minutes"; return; }
    grep -qxF "bundle=$BUNDLE" "$d/backup.meta" || { echo "backup.meta is for another bundle"; return; }
    grep -qxF "udid=$DEV" "$d/backup.meta" || { echo "backup.meta is for another device"; return; }
    # Every file the phone lists, same relative path and size.
    n=0
    while IFS="$(printf '\t')" read -r rel size; do
        f="$d/$rel"
        got="$( { stat -f %z "$f" 2>/dev/null || stat -c %s "$f" 2>/dev/null; } || true )"
        if [ ! -f "$f" ] || [ "$got" != "$size" ]; then
            echo "$rel: phone $size bytes, folder ${got:-missing}"; return
        fi
        n=$((n + 1))
    done < "$LISTING"
    # Nothing that is not on the phone.
    if [ "$( (cd "$d" && find . -type f ! -path ./sha256.txt ! -path ./backup.meta) | sed 's|^\./||' | LC_ALL=C sort)" \
            != "$(cut -f1 "$LISTING" | LC_ALL=C sort)" ]; then
        echo "its files are not exactly the phone's savedata files"; return
    fi
    [ "$n" -gt 0 ] || { echo "the phone lists no save to stand for"; return; }
    [ -s "$d/sha256.txt" ] || { echo "no sha256.txt"; return; }
    # Only paths inside the folder: "<sha>  <relpath>", no absolute path, no "..".
    if grep -vqE '^[0-9a-f]{64}  [^/]' "$d/sha256.txt" || grep -qE '(^|/)\.\.(/|$)' "$d/sha256.txt"; then
        echo "sha256.txt has lines that are not relative paths inside the folder"; return
    fi
    # sha256.txt covers exactly the phone's files (none left unchecked, none extra).
    if [ "$(cut -c67- "$d/sha256.txt" | LC_ALL=C sort)" != "$(cut -f1 "$LISTING" | LC_ALL=C sort)" ]; then
        echo "sha256.txt does not list exactly the phone's savedata files"; return
    fi
    ( cd "$d" && shasum -a 256 -c --status sha256.txt ) 2>/dev/null || { echo "sha256.txt does not check"; return; }
}
BK="${GOW2_IOS_SAVE_BACKUP_DIR:-$HOME/Documents/GoW2 Saves}/$(date +%Y-%m-%d_%H%M%S)-iphone-cli"
# An independent, phone-side listing to verify the copy against (Codex review MAJOR,
# 2026-09-28). Lists the stable Documents/ -- not Documents/savedata directly, which
# does not exist on a first install and would make the listing itself fail -- and
# filters client-side, exactly like IOSSaveSyncer.swift's phoneListsSavedata()/
# fetchPhone(): a listing failure is never read as "the phone has no save".
# One private temp dir (BSD mktemp only randomizes TRAILING X's: a ".XXXXXX.json"
# template is a fixed name that collides with the next run).
LT="$(mktemp -d "${TMPDIR:-/tmp}/gow2_ios_savelist.XXXXXX")"
LJ="$LT/list.json"; LP="$LT/list.plist"; LISTING="$LT/rows.tsv"; AJ="$LT/apps.json"
# First install of this bundle? Asked of the phone's own app list (Codex review
# IMPORTANT, Task 7): only an explicit "not installed" skips the backup; a failed or
# unreadable app list refuses, like a failed file listing.
if ! xcrun devicectl device info apps --device "$DEV" --bundle-id "$BUNDLE" -t 60 -j "$AJ" -q; then
    rm -rf "$LT"
    echo "could not list the apps on the phone: nothing installed." >&2
    exit 1
fi
# devicectl can exit 0 and still write a failed outcome (Codex re-review CRITICAL):
# an empty array is only believed under outcome "success".
NAPPS=""
if [ "$(plutil -extract info.outcome raw -o - "$AJ" 2>/dev/null || true)" = success ]; then
    NAPPS="$(plutil -extract result.apps raw -o - "$AJ" 2>/dev/null || true)"
fi
case "$NAPPS" in
    ''|*[!0-9]*) rm -rf "$LT"; echo "unreadable phone app list: nothing installed." >&2; exit 1 ;;
esac
if [ "$NAPPS" = 0 ]; then
    rm -rf "$LT"
    echo "$BUNDLE is not on the phone yet (first install): no saves to back up."
else
    # The app is on the phone: always its own listing of Documents/savedata, whether or not
    # the caller handed a backup folder -- that folder is checked against it.
    if ! xcrun devicectl device info files --device "$DEV" --domain-type appDataContainer \
            --domain-identifier "$BUNDLE" --subdirectory Documents -t 120 -j "$LJ" -q; then
        rm -rf "$LT"
        echo "could not list Documents on the phone: nothing installed." >&2
        exit 1
    fi
    # A listing with no result.files array (a failed outcome written with rc 0) is not
    # "no save" either.
    if ! plutil -convert xml1 -o "$LP" "$LJ" 2>/dev/null \
            || ! /usr/libexec/PlistBuddy -c "Print :result:files" "$LP" > /dev/null 2>&1; then
        rm -rf "$LT"
        echo "unreadable phone file listing: nothing installed." >&2
        exit 1
    fi
    # <relpath under savedata/>\t<size>, files only (no directory entries).
    # Every entry the phone listed is read (Codex review CRITICAL, Task 7: stopping at the
    # first entry without a relativePath skipped the saves listed after it); an entry
    # that cannot be described -- no path, or a savedata file without isDirectory/size --
    # refuses the install instead of being read as "nothing to keep".
    : > "$LISTING"
    NFILES="$(plutil -extract result.files raw -o - "$LJ" 2>/dev/null || true)"
    [ "$(plutil -extract info.outcome raw -o - "$LJ" 2>/dev/null || true)" = success ] || NFILES=bad
    case "$NFILES" in
        ''|*[!0-9]*) rm -rf "$LT"; echo "unreadable phone file listing: nothing installed." >&2; exit 1 ;;
    esac
    pb() { /usr/libexec/PlistBuddy -c "Print :result:files:$1" "$LP" 2>/dev/null; }
    i=0
    while [ "$i" -lt "$NFILES" ]; do
        rel="$(pb "$i:relativePath")" || { rm -rf "$LT"; echo "unreadable entry $i in the phone file listing (no relativePath): nothing installed." >&2; exit 1; }
        case "$rel" in
            savedata/*)
                isdir="$(pb "$i:resources:isDirectory")" \
                    || { rm -rf "$LT"; echo "unreadable entry $rel in the phone file listing (no isDirectory): nothing installed." >&2; exit 1; }
                if [ "$isdir" != true ]; then
                    size="$(pb "$i:metadata:size")" || size=""   # set -e: a failed lookup is data here
                    case "$size" in
                        ''|*[!0-9]*) rm -rf "$LT"; echo "unreadable entry $rel in the phone file listing (no size): nothing installed." >&2; exit 1 ;;
                    esac
                    printf '%s\t%s\n' "${rel#savedata/}" "$size" >> "$LISTING"
                fi
                ;;
        esac
        i=$((i + 1))
    done
    HANDSHAKE=""
    if [ -n "${GOW2_IOS_SAVES_BACKUP_DIR:-}" ]; then
        why="$(handshake_problem "$GOW2_IOS_SAVES_BACKUP_DIR")"
        if [ -z "$why" ]; then
            HANDSHAKE="$GOW2_IOS_SAVES_BACKUP_DIR"
        else
            echo "GOW2_IOS_SAVES_BACKUP_DIR=$GOW2_IOS_SAVES_BACKUP_DIR not accepted ($why): backing up the phone's saves here." >&2
        fi
    fi
    if [ -n "$HANDSHAKE" ]; then
        echo "phone saves already backed up by the caller to $HANDSHAKE (verified against the phone's own listing," \
             "$(wc -l < "$LISTING" | tr -d ' ') files; sha256.txt checks; fresh; same bundle and device)"
    elif [ -s "$LISTING" ]; then
        mkdir -p "$BK"
        if ! xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
                --domain-identifier "$BUNDLE" --source Documents/savedata --destination "$BK"; then
            rm -rf "$BK" "$LT"
            echo "could not copy Documents/savedata from the phone to $BK: nothing installed." >&2
            echo "Unlock the phone, check the cable and run it again (or use the Mac launcher's \"Instalar no iPhone\")." >&2
            exit 1
        fi
        # Verify every phone-listed file landed, same size (Codex review MAJOR): this is
        # what actually catches a partial or truncated copy that still exited 0.
        while IFS="$(printf '\t')" read -r rel size; do
            f="$BK/$rel"
            got="$( { stat -f %z "$f" 2>/dev/null || stat -c %s "$f" 2>/dev/null; } || true )"
            if [ ! -f "$f" ] || [ "$got" != "$size" ]; then
                rm -rf "$BK" "$LT"
                echo "backup verification against the phone's listing failed for $rel" \
                     "(phone: $size bytes, backup: ${got:-missing}): nothing installed." >&2
                exit 1
            fi
        done < "$LISTING"
        ( cd "$BK" && find . -type f ! -name sha256.txt ! -name backup.meta -exec shasum -a 256 {} + | sed 's|  \./|  |' > sha256.txt )
        # Which bundle/device this backup belongs to (the launcher writes the same file).
        printf 'bundle=%s\nudid=%s\n' "$BUNDLE" "$DEV" > "$BK/backup.meta"
        echo "phone saves backed up to $BK (verified against the phone's own listing, $(wc -l < "$LISTING" | tr -d ' ') files)"
    else
        echo "the phone lists no Documents/savedata yet: nothing to back up."
    fi
    rm -rf "$LT"
fi
xcrun devicectl device install app --device "$DEV" "$APP"
if [ "${1:-}" = "--data" ]; then
    cp() { xcrun devicectl device copy to --device "$DEV" --domain-type appDataContainer \
               --domain-identifier "$BUNDLE" --source "$1" --destination "$2"; }
    # First mark the phone's install incomplete (the launcher's own marker), so a complete
    # manifest from an earlier install can never vouch for files this run replaces.
    MARK="$(mktemp -d)"; trap 'rm -rf "$MARK"' EXIT
    printf 'gow2-install 1\nincomplete\n' > "$MARK/gow2-install.manifest"
    cp "$MARK/gow2-install.manifest" Documents/gow2-install.manifest
    cp "$G/EBOOT.ELF" Documents/EBOOT.ELF
    cp "$G/extracted/USRDIR" Documents/USRDIR
    cp "$G/movie_cache" Documents/movie_cache
    echo "note: the app now says \"Jogo não instalado\" until the Mac launcher's \"Instalar no iPhone\" writes" \
         "Documents/gow2-install.manifest. Files up to 64 MiB are checked there by downloading them back;" \
         "files over 64 MiB without the launcher's pushed-hash record (gow2.psarc, 6.5 GB) are copied again." >&2
fi
echo "GOW2_IOS_INSTALL_OK"
