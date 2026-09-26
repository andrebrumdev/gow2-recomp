#!/bin/bash
# Regression test for the xcodebuild failure: error: The file "licenses"
# couldn't be opened because there is no such file. (in target 'GoW2')
#
# Root cause: xcodegen's `type: folder` sources resolve `path` relative to
# the spec file (ios/) and hardcode sourceTree=SOURCE_ROOT (verified
# empirically: even an absolute `path` gets silently rewritten back to a
# spec-relative one). SOURCE_ROOT means the .xcodeproj's own directory, and
# build_ios.sh always generates into $B/xcode -- never next to project.yml
# -- so a `type: folder` source under Generated/ resolves to
# $B/xcode/Generated/licenses, which never exists. The fix copies the
# licenses folder into the bundle with a build script that reads the
# absolute $GOW2_IOS_HERE build setting at build time instead.
#
# This runs real xcodegen (fast, no compile) against the actual
# ios/project.yml, generated out-of-tree like build_ios.sh does, and
# inspects the resulting project.pbxproj. No xcodebuild needed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="$(cd "$HERE/.." && pwd)"
command -v xcodegen >/dev/null 2>&1 || { echo "SKIP: xcodegen not installed"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
F() { echo "FAIL: $*"; fail=1; }

IOS="$T/ios"
mkdir -p "$IOS/Generated/licenses"
cp "$PORT/ios/project.yml" "$IOS/project.yml"
cp -R "$PORT/ios/Sources" "$IOS/Sources"
cp "$PORT/ios/GoW2.entitlements" "$IOS/GoW2.entitlements"
: > "$IOS/Generated/gow2.env"
: > "$IOS/Generated/Gow2.xcconfig"
: > "$IOS/Generated/licenses/FFmpeg-COPYING.LGPLv2.1.txt"

# Out-of-tree, at the same relative depth build_ios.sh uses for "$B/xcode"
# (two levels below the checkout that holds ios/), never next to project.yml.
PROJ="$T/build-ios/xcode"
mkdir -p "$PROJ"
xcodegen generate --spec "$IOS/project.yml" --project "$PROJ" --quiet \
    > "$T/xcodegen.log" 2>&1 || { cat "$T/xcodegen.log" >&2; F "xcodegen generate failed"; }

PBX="$PROJ/GoW2.xcodeproj/project.pbxproj"
if [ -f "$PBX" ]; then
    # The defect signature: a file/folder reference rooted at SOURCE_ROOT
    # (= the .xcodeproj's own directory) still carrying a path relative to
    # Generated/ -- that never resolves once the project is generated
    # out-of-tree.
    grep -E 'path = "?Generated/[^;"]*"?; sourceTree = SOURCE_ROOT;' "$PBX" \
        && F "a Generated/ path is rooted at SOURCE_ROOT -- won't resolve once xcodegen writes the project out-of-tree (the 'licenses' bug)"

    # The fix in place: licenses copied in by a build script reading the
    # absolute $GOW2_IOS_HERE build setting, not a folder source reference.
    grep -q "Copy FFmpeg licenses" "$PBX" || F "expected the 'Copy FFmpeg licenses' build script phase"
    grep -q '\$GOW2_IOS_HERE/Generated/licenses' "$PBX" || F "the licenses script must reference the absolute \$GOW2_IOS_HERE build setting"
else
    F "no project.pbxproj generated"
fi

[ "$fail" = 0 ] && echo "OK: test_ios_xcodegen_licenses.sh"
exit "$fail"
