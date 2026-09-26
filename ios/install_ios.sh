#!/bin/bash
# install_ios.sh [--data] -- installs the built GoW2.app on the device (a
# reinstall = re-sign: the app's data container is kept). --data also copies
# EBOOT.ELF, USRDIR and movie_cache into the container's Documents (first
# install; devicectl skips files that did not change), after overwriting
# Documents/gow2-install.manifest with the incomplete marker. Final line
# "GOW2_IOS_INSTALL_OK" on success.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/ios_env.sh"
[ -n "$DEV" ] || { echo "set GOW2_IOS_DEVICE in local.env" >&2; exit 1; }
[ -d "$APP" ] || { echo "no app at $APP: run build_ios.sh" >&2; exit 1; }
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
