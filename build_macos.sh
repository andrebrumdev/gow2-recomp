#!/usr/bin/env bash
# Build the God of War II HD native macOS/arm64 host (phase F4 of
# ps3recomp/docs/MACOS_PORT_PLAN.md). The POSIX counterpart of build_d3d.sh.
#
# Assumes the lift already ran:
#   python ../ps3recomp/tools/ppu_lifter.py EBOOT.ELF --functions functions.json \
#          --output recomp_macos
#
# Usage: ./build_macos.sh [lift-dir]        (default: recomp_macos)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PS3="$HERE/../ps3recomp"
LIFT="${1:-$HERE/recomp_macos}"
OUT="$HERE/boot_gow2"

if [ ! -f "$LIFT/ppu_recomp.h" ]; then
    echo "no lift output in $LIFT -- run ppu_lifter.py first" >&2
    exit 1
fi

RUNTIME_LIB="$PS3/build-macos/libps3recomp_runtime.a"
if [ ! -f "$RUNTIME_LIB" ]; then
    echo "runtime library missing; build it first:" >&2
    echo "  cmake -B $PS3/build-macos -G Ninja -DCMAKE_BUILD_TYPE=Release $PS3" >&2
    echo "  cmake --build $PS3/build-macos" >&2
    exit 1
fi

INC=(-I "$LIFT"
     -I "$PS3/include"
     -I "$PS3/runtime/ppu"
     -I "$PS3/runtime/syscalls"
     -I "$PS3/runtime/spu"
     -I "$PS3/runtime/prx"
     -I "$PS3/runtime/memory"
     -I "$PS3/libs/system" -I "$PS3/libs/spurs" -I "$PS3/libs/sync"
     -I "$PS3/libs/video"  -I "$PS3/libs/audio" -I "$PS3/libs/network"
     -I "$PS3/libs/codec")

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
JOBS=$(( JOBS > 6 ? 6 : JOBS ))   # each chunk peaks near 1 GB of compiler RSS

echo "=== 1. lifted chunks -> .o (-P $JOBS) ==="
cd "$LIFT"
t0=$(date +%s)
# Only rebuild chunks whose object is missing or stale: a full rebuild of all
# 31 is a couple of minutes, and this loop is run repeatedly while iterating.
ls ppu_recomp_*.cpp ppu_stubs.cpp 2>/dev/null | while read -r f; do
    if [ ! -f "$f.o" ] || [ "$f" -nt "$f.o" ]; then echo "$f"; fi
done | xargs -P "$JOBS" -I {} sh -c \
    'clang++ -std=c++20 -O0 -w -c -I . -I "$2/include" -I "$2/runtime/ppu" "$1" -o "$1.o" 2> "$1.cclog"' \
    _ {} "$PS3"
echo "  dur=$(( $(date +%s) - t0 ))s objs=$(ls ./*.cpp.o 2>/dev/null | wc -l | tr -d ' ') errors=$(cat ./*.cclog 2>/dev/null | grep -c 'error:' || true)"

echo "=== 2. runtime PPU sources -> .o ==="
cd "$HERE"
for src in ppu_loader ppu_imports ppu_hle ppu_sysprx ppu_fs; do
    clang++ -std=c++20 -O0 -w -c "${INC[@]}" "$PS3/runtime/ppu/$src.cpp" -o "$LIFT/$src.o"
done

echo "=== 3. HLE NID table -> .o ==="
# ppu_hle_register_all() is a weak no-op in the runtime; without a strong
# override every firmware call the game makes logs "unresolved NID" and returns
# nothing. Regenerated from the /* NID */ annotations in the HLE sources.
mkdir -p "$LIFT/gen"
# sceNpCommerce.c and sceNpCommerce2.c both define the whole sceNpCommerce2*
# API (different context types, same symbols), so linking both objects fails
# with duplicate symbols. Keep the "2" one, which matches the module name.
# GoW2 imports neither -- this only avoids dragging the collision in.
LIBS=$(ls "$PS3"/libs/*/*.c | xargs -n1 basename | sed 's/\.c$//' | sort -u \
       | grep -vx 'sceNpCommerce')
# shellcheck disable=SC2086
"$PS3/.venv/bin/python" "$PS3/tools/gen_hle_nids.py" \
    --out "$LIFT/gen/ppu_hle_nids.cpp" $LIBS > /dev/null
clang++ -std=c++20 -O0 -w -c "${INC[@]}" -I "$PS3/libs" "$LIFT/gen/ppu_hle_nids.cpp" -o "$LIFT/ppu_hle_nids.o"

echo "=== 4. boot host -> .o ==="
clang++ -std=c++20 -O0 -w -c "${INC[@]}" "$HERE/boot_macos.cpp" -o "$LIFT/boot_macos.o"

echo "=== 5. link ==="
SDL_FLAGS=$(pkg-config --libs sdl2)
VK_FLAGS=""
if [ -f /opt/homebrew/lib/libvulkan.dylib ]; then
    VK_FLAGS="-L/opt/homebrew/lib -lvulkan"
fi

# The guest's CRT recurses deeply under -O0; the default 8 MB main-thread stack
# is not enough. Windows uses -Wl,--stack,33554432 for the same reason.
clang++ -std=c++20 -O0 \
    "$LIFT"/*.cpp.o \
    "$LIFT"/ppu_loader.o "$LIFT"/ppu_imports.o "$LIFT"/ppu_hle.o \
    "$LIFT"/ppu_sysprx.o "$LIFT"/ppu_fs.o \
    "$LIFT"/ppu_hle_nids.o "$LIFT"/boot_macos.o \
    "$RUNTIME_LIB" \
    -framework Metal -framework QuartzCore -framework Foundation \
    -framework Cocoa \
    $SDL_FLAGS $VK_FLAGS -lm \
    -Wl,-stack_size,0x2000000 \
    -o "$OUT"

echo
ls -lh "$OUT"
echo "*** $OUT built ***"
echo
echo "run it with:  ./rodar_gow2.sh"
