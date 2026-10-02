#!/bin/bash
# The desktop key handling of the Vulkan pump (F11 / Alt+Enter fullscreen, Esc -> vulkan_quit_now -> _exit(0)) must be
# compiled out on Android: there the SDL thread processes events, and two Esc presses (`adb shell input keyevent 111`)
# killed the app. Static check: inside the SDL_KEYDOWN case of rsx_vulkan_backend_pump_messages, every
# vulkan_quit_now / SDL_SetWindowFullscreen line must sit inside an `#ifndef __ANDROID__` block.
# Usage: test_vulkan_android_keys.sh [file]   (default: libs/video/rsx_vulkan_backend.c)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; F="${1:-$HERE/../../../libs/video/rsx_vulkan_backend.c}"
fails=0; bad() { echo "FAIL: $*"; fails=$((fails + 1)); }
start="$(grep -n 'case SDL_KEYDOWN' "$F" | head -1 | cut -d: -f1)"
[ -n "$start" ] || { echo "FAIL: SDL_KEYDOWN case not found"; exit 1; }
# the case ends at the first 'break;' followed by a closing brace at case level
body="$(sed -n "$start,\$p" "$F" | awk '/^        }/ {print; exit} {print}')"
[ -n "$body" ] || { echo "FAIL: case body empty"; exit 1; }
printf '%s\n' "$body" | grep -q 'vulkan_quit_now' || bad "no vulkan_quit_now found in the case (test out of date?)"
out="$(printf '%s\n' "$body" | awk '
  /^#[ ]*ifndef __ANDROID__/ {d++; next}
  /^#[ ]*if/ {if (d) d++; next}
  /^#[ ]*endif/ {if (d) d--; next}
  /vulkan_quit_now|SDL_SetWindowFullscreen/ {if (!d) print "outside #ifndef __ANDROID__: " $0}')"
[ -z "$out" ] || bad "$out"
[ "$fails" = 0 ] && { echo "test_vulkan_android_keys: PASS"; exit 0; }
echo "test_vulkan_android_keys: FAIL ($fails)"; exit 1
