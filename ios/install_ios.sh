#!/bin/bash
# install_ios.sh [--data] -- installs the built GoW2.app on the device (a
# reinstall = re-sign: the app's data container is kept). --data also copies
# EBOOT.ELF, USRDIR and movie_cache into the container's Documents (first
# install; devicectl skips files that did not change). Final line
# "GOW2_IOS_INSTALL_OK" on success.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/ios_env.sh"
[ -n "$DEV" ] || { echo "set GOW2_IOS_DEVICE in local.env" >&2; exit 1; }
[ -d "$APP" ] || { echo "no app at $APP: run build_ios.sh" >&2; exit 1; }
xcrun devicectl device install app --device "$DEV" "$APP"
if [ "${1:-}" = "--data" ]; then
    cp() { xcrun devicectl device copy to --device "$DEV" --domain-type appDataContainer \
               --domain-identifier "$BUNDLE" --source "$1" --destination "$2"; }
    cp "$G/EBOOT.ELF" Documents/EBOOT.ELF
    cp "$G/extracted/USRDIR" Documents/USRDIR
    cp "$G/movie_cache" Documents/movie_cache
fi
echo "GOW2_IOS_INSTALL_OK"
