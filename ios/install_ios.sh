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
# nothing is installed. GOW2_IOS_SAVES_BACKED_UP=1 = the caller already did it (the Mac
# launcher does) or there is nothing to keep (first install of this bundle).
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/ios_env.sh"
[ -n "$DEV" ] || { echo "set GOW2_IOS_DEVICE in local.env" >&2; exit 1; }
[ -d "$APP" ] || { echo "no app at $APP: run build_ios.sh" >&2; exit 1; }
if [ "${GOW2_IOS_SAVES_BACKED_UP:-}" != 1 ]; then
    BK="${GOW2_IOS_SAVE_BACKUP_DIR:-$HOME/Documents/GoW2 Saves}/$(date +%Y-%m-%d_%H%M%S)-iphone-cli"
    # An independent, phone-side listing to verify the copy against (Codex review MAJOR,
    # 2026-09-28). Lists the stable Documents/ -- not Documents/savedata directly, which
    # does not exist on a first install and would make the listing itself fail -- and
    # filters client-side, exactly like IOSSaveSyncer.swift's phoneListsSavedata()/
    # fetchPhone(): a listing failure is never read as "the phone has no save".
    # One private temp dir (BSD mktemp only randomizes TRAILING X's: a ".XXXXXX.json"
    # template is a fixed name that collides with the next run).
    LT="$(mktemp -d "${TMPDIR:-/tmp}/gow2_ios_savelist.XXXXXX")"
    LJ="$LT/list.json"; LP="$LT/list.plist"; LISTING="$LT/rows.tsv"
    if ! xcrun devicectl device info files --device "$DEV" --domain-type appDataContainer \
            --domain-identifier "$BUNDLE" --subdirectory Documents -t 120 -j "$LJ" -q; then
        rm -rf "$LT"
        echo "could not list Documents on the phone: nothing installed." >&2
        echo "First install of this bundle (not on the phone yet)? Re-run with GOW2_IOS_SAVES_BACKED_UP=1." >&2
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
    : > "$LISTING"
    i=0
    while rel="$(/usr/libexec/PlistBuddy -c "Print :result:files:$i:relativePath" "$LP" 2>/dev/null)"; do
        case "$rel" in
            savedata/*)
                isdir="$(/usr/libexec/PlistBuddy -c "Print :result:files:$i:resources:isDirectory" "$LP" 2>/dev/null)"
                if [ "$isdir" != true ]; then
                    size="$(/usr/libexec/PlistBuddy -c "Print :result:files:$i:metadata:size" "$LP" 2>/dev/null)"
                    printf '%s\t%s\n' "${rel#savedata/}" "${size:-0}" >> "$LISTING"
                fi
                ;;
        esac
        i=$((i + 1))
    done
    if [ -s "$LISTING" ]; then
        mkdir -p "$BK"
        if ! xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
                --domain-identifier "$BUNDLE" --source Documents/savedata --destination "$BK"; then
            rm -rf "$BK" "$LT"
            echo "could not copy Documents/savedata from the phone to $BK: nothing installed." >&2
            echo "First install of this bundle (no saves yet), or saves already backed up by hand?" \
                 "Re-run with GOW2_IOS_SAVES_BACKED_UP=1." >&2
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
        ( cd "$BK" && find . -type f ! -name sha256.txt -exec shasum -a 256 {} + | sed 's|  \./|  |' > sha256.txt )
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
