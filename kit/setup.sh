#!/usr/bin/env bash
# kit/setup.sh -- build GoW2 Recomp for macOS (Apple Silicon) from YOUR copy of the game.
#
#   ./kit/setup.sh <PS3_GAME folder> [--rap <license.rap>] [--elf <EBOOT.ELF>]
#
#   PS3_GAME folder  the game's folder with USRDIR/EBOOT.BIN and USRDIR/gow2.psarc,
#                    from your RPCS3 dev_hdd0/game/NPUA80491 or your PS3.
#   --rap            your license for the game, UP9000-NPUA80491_00-GODOFWARIIHDUS00.rap.
#                    Found by itself in RPCS3's dev_hdd0/home/*/exdata, next to the
#                    game folder or in ~/Downloads.
#   --elf            an EBOOT.ELF you already decrypted (skips the decryption).
#   Supported: God of War II HD, NPUA80491 v01.00 (SHA-256 of the ELF below).
#
# What it does, all locally, nothing is downloaded:
#   1. checks the tools (Xcode Command Line Tools, CMake, Ninja, Python >= 3.11);
#   2. decrypts USRDIR/EBOOT.BIN with your license (tools/unself in the engine)
#      and links the game folder as extracted/;
#   3. extracts the movies and WADs the host player reads into movie_cache/;
#   4. recompiles the PPU code (pinned lifter + patch scripts + kit delta) and
#      checks every generated file against kit/ppu_lift.sha256;
#   5. recompiles the seven SPU programs, checked against kit/spu_lift.sha256;
#   6. builds the engine runtime and links ./g2play.
#   7. builds the launcher app, GoW2 Recomp.app (also "Instalar no iPhone").
# Re-running skips the steps whose output already verifies.
#
# Env: PS3_ENGINE_ROOT (default ../ps3recomp), PY (a Python >= 3.11), JOBS,
#      KIT_TOOLS (cpp = build and use ps3kit, the default; py = the Python tools).
set -euo pipefail

EBOOT_SHA=23cfd435be284adb83745c3e1bcad7b7660782470f71255cb74a1d2be8b1163b
CONTENT_ID=UP9000-NPUA80491_00-GODOFWARIIHDUS00
PPU_LIFTER_REV=5b004fc7

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31merro:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,26p' "$0"; exit 2; }
GAME_ARG=""; RAP_IN=""; ELF_IN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --rap) RAP_IN="${2:-}"; shift 2 ;;
        --elf) ELF_IN="${2:-}"; shift 2 ;;
        -h|--help) usage ;;
        *) [ -z "$GAME_ARG" ] || usage; GAME_ARG="$1"; shift ;;
    esac
done
[ -n "$GAME_ARG" ] || usage
HERE="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$HERE/kit"
. "$KIT/lib/stages.sh"
PPU_FILES="ppu_recomp.h ppu_recomp_000.cpp ppu_recomp_001.cpp ppu_recomp_002.cpp ppu_recomp_003.cpp ppu_recomp_004.cpp ppu_recomp_005.cpp ppu_recomp_006.cpp"
ENGINE="$(cd "${PS3_ENGINE_ROOT:-$HERE/../ps3recomp}" 2>/dev/null && pwd)" \
    || die "motor ps3recomp nao encontrado (esperado em $HERE/../ps3recomp ou PS3_ENGINE_ROOT)"
GAME_IN="$(cd "$GAME_ARG" && pwd)" || die "pasta do jogo nao encontrada: $GAME_ARG"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

# ---- 1. tools ---------------------------------------------------------------
say "1/7 ferramentas"
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || die "o kit e' para macOS em Apple Silicon (arm64)"
command -v clang >/dev/null || die "falta o clang: xcode-select --install"
command -v cmake >/dev/null || die "falta o CMake: brew install cmake"
command -v ninja >/dev/null || die "falta o Ninja: brew install ninja"
. "$KIT/lib/pick_python.sh"
. "$KIT/lib/cpython_src.sh"
KIT_ROOT="$(cd "$HERE/.." && pwd)"
rc=0; PY="$(kit_pick_python "$HERE")" || rc=$?
if [ "$rc" = 2 ]; then die "PY nao e' um Python >= 3.11"; fi
if [ "$rc" = 1 ]; then
    # '|| true': with no tarball, ls fails and pipefail + errexit would exit silently.
    TB="$(ls "$KIT_ROOT"/third_party/cpython/Python-*.tar.xz 2>/dev/null | head -1 || true)"
    [ -n "$TB" ] || die "falta Python >= 3.11 (brew install python) e este kit nao traz o codigo do CPython"
    echo "   nenhum Python >= 3.11: compilando o do kit (uma vez, alguns minutos)"
    mkdir -p "$HERE/.kit_tools"
    kit_build_python "$TB" "$(sed -n 's/^PYTHON_SHA256=//p' "$KIT/python.lock")" \
        "$HERE/.kit_tools/python" "$HERE/.kit_tools/cpython-build" > "$HERE/.kit_tools/cpython.log" 2>&1 \
        || die "a compilacao do Python do kit falhou (log: .kit_tools/cpython.log)"
    PY="$HERE/.kit_tools/python/bin/python3"
fi
export PY
# apply_all_patches.sh has its own discovery that ignores PY; point it at the same one.
export PS3_PATCH_PYTHON="$PY"
echo "   clang $(clang --version | head -1 | sed 's/.*version //;s/ .*//'), cmake $(cmake --version | head -1 | awk '{print $3}'), $("$PY" --version)"
KIT_TOOLS="${KIT_TOOLS:-cpp}"
case "$KIT_TOOLS" in py|cpp) ;; *) die "KIT_TOOLS must be py or cpp (got '$KIT_TOOLS')" ;; esac
export KIT_TOOLS
if [ "$KIT_TOOLS" = cpp ]; then
    mkdir -p "$HERE/.kit_tools"
    { cmake -S "$ENGINE/tools/kit" -B "$HERE/.kit_tools/ps3kit" -G Ninja -DCMAKE_BUILD_TYPE=Release \
      && cmake --build "$HERE/.kit_tools/ps3kit" --target ps3kit; } > "$HERE/.kit_tools/ps3kit.log" 2>&1 \
        || die "nao compilou o ps3kit (log: .kit_tools/ps3kit.log). KIT_TOOLS=py usa as ferramentas Python."
    PS3KIT="$HERE/.kit_tools/ps3kit/ps3kit"; export PS3KIT
    echo "   ps3kit: $("$PS3KIT" --version)"
else
    unset PS3KIT   # the py path must not pick up a ps3kit from the caller's environment
fi

# ---- 2. game files ----------------------------------------------------------
say "2/7 arquivos do jogo"
[ -f "$GAME_IN/USRDIR/gow2.psarc" ] || die "nao achei USRDIR/gow2.psarc em $GAME_IN"
elf_ok() { [ -f "$1" ] && [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$EBOOT_SHA" ]; }
if [ -n "$ELF_IN" ]; then
    elf_ok "$ELF_IN" || die "$ELF_IN nao e' o EBOOT.ELF suportado (God of War II HD NPUA80491 v01.00)"
    [ "$(cd "$(dirname "$ELF_IN")" && pwd)/$(basename "$ELF_IN")" = "$HERE/EBOOT.ELF" ] || cp "$ELF_IN" "$HERE/EBOOT.ELF"
    echo "   EBOOT.ELF fornecido e conferido"
elif elf_ok "$HERE/EBOOT.ELF"; then
    echo "   EBOOT.ELF ja' descriptografado e conferido"
else
    [ -f "$GAME_IN/USRDIR/EBOOT.BIN" ] || die "nao achei USRDIR/EBOOT.BIN em $GAME_IN"
    if [ -z "$RAP_IN" ]; then
        for c in "$HOME/Library/Application Support/rpcs3/dev_hdd0/home/"*/exdata/"$CONTENT_ID.rap" \
                 "$GAME_IN/$CONTENT_ID.rap" "$GAME_IN/../$CONTENT_ID.rap"; do
            [ -f "$c" ] && { RAP_IN="$c"; break; }
        done
        [ -n "$RAP_IN" ] || RAP_IN="$(find "$HOME/Downloads" -maxdepth 3 -name "$CONTENT_ID.rap" 2>/dev/null | head -1)"
    fi
    [ -n "$RAP_IN" ] && [ -f "$RAP_IN" ] || die "falta a licenca do jogo ($CONTENT_ID.rap). Passe --rap <arquivo>; no RPCS3 ela fica em dev_hdd0/home/<usuario>/exdata."
    mkdir -p "$HERE/.kit_tools"
    clang -O2 "$ENGINE/tools/unself/ps3_unself.c" -lz -o "$HERE/.kit_tools/ps3_unself" \
        || die "nao compilou o descriptografador (tools/unself)"
    "$HERE/.kit_tools/ps3_unself" "$GAME_IN/USRDIR/EBOOT.BIN" "$HERE/EBOOT.ELF" --rap "$RAP_IN" \
        || die "a descriptografia do EBOOT.BIN falhou"
    elf_ok "$HERE/EBOOT.ELF" || die "o EBOOT.BIN descriptografado nao e' a versao suportada (NPUA80491 v01.00)"
    echo "   EBOOT.BIN descriptografado com $(basename "$RAP_IN") e conferido"
fi
if [ -L "$HERE/extracted" ] || [ ! -e "$HERE/extracted" ]; then
    ln -sfn "$GAME_IN" "$HERE/extracted"
elif [ "$(cd "$HERE/extracted" && pwd -P)" != "$(cd "$GAME_IN" && pwd -P)" ]; then
    echo "   extracted/ ja' existe (pasta real) -- mantida"
fi
echo "   extracted -> $GAME_IN"

# ---- 3. movie_cache -----------------------------------------------------------
say "3/7 filmes e WADs (movie_cache)"
mkdir -p "$HERE/movie_cache"
if (cd "$HERE/movie_cache" && shasum -a 256 -c "$KIT/movie_cache.sha256" >/dev/null 2>&1); then
    echo "   ja' extraidos e verificados"
else
    while read -r _sum name; do
        lc="$(printf '%s' "$name" | tr 'A-Z' 'a-z')"
        case "$lc" in *.m2v|*.wav) src="/_movies/$lc" ;; *) src="/wad/$lc" ;; esac
        [ -f "$HERE/movie_cache/$name" ] && (cd "$HERE/movie_cache" && grep " $name\$" "$KIT/movie_cache.sha256" | shasum -a 256 -c - >/dev/null 2>&1) && continue
        echo "   $src"
        if [ -n "${PS3KIT:-}" ]; then
            "$PS3KIT" psarc-extract "$GAME_IN/USRDIR/gow2.psarc" "$src" "$HERE/movie_cache/$name" >/dev/null
        else
            "$PY" "$ENGINE/tools/psarc_extract.py" "$GAME_IN/USRDIR/gow2.psarc" "$src" "$HERE/movie_cache/$name" >/dev/null
        fi
    done < "$KIT/movie_cache.sha256"
    (cd "$HERE/movie_cache" && shasum -a 256 -c "$KIT/movie_cache.sha256" >/dev/null) \
        || die "movie_cache nao confere com kit/movie_cache.sha256 (psarc diferente?)"
    echo "   17 arquivos verificados"
fi
# shellcheck disable=SC2046
stage_capture movie_cache "$HERE/movie_cache" $(awk '{print $2}' "$KIT/movie_cache.sha256")
kit_stop_after 3

# ---- 4. PPU recompilation ---------------------------------------------------------
say "4/7 recompilacao do PPU"
LIFT="$HERE/recomp_macos_e435"
if [ -d "$LIFT" ] && (cd "$LIFT" && shasum -a 256 -c "$KIT/ppu_lift.sha256" >/dev/null 2>&1); then
    echo "   $LIFT ja' confere"
else
    T="$(mktemp -d "${TMPDIR:-/tmp}/gow2_ppu.XXXXXX")"
    trap 'rm -rf "$T"' EXIT
    if [ -d "$ENGINE/tools_pinned/$PPU_LIFTER_REV/tools" ]; then
        cp -R "$ENGINE/tools_pinned/$PPU_LIFTER_REV/tools" "$T/"
    else
        git -C "$ENGINE" archive "$PPU_LIFTER_REV" tools | tar -x -C "$T"
    fi
    echo "   lifter $PPU_LIFTER_REV (~30 s)"
    "$PY" "$T/tools/ppu_lifter.py" "$HERE/EBOOT.ELF" --functions "$HERE/functions.json" \
        --config "$HERE/config/gow2_recomp.toml" -o "$T/lift" -j "$JOBS" > "$T/lift.log" 2>&1 \
        || { tail -20 "$T/lift.log"; die "o lifter falhou"; }
    # The lifter stamps its git revision; an exported snapshot has no git, so
    # it writes "unknown". The revision is the pinned one.
    sed -i '' "s|/\* lifter-rev: unknown \*/|/* lifter-rev: $PPU_LIFTER_REV */|" "$T"/lift/ppu_recomp_00?.cpp
    # shellcheck disable=SC2086
    stage_capture ppu_raw "$T/lift" $PPU_FILES
    echo "   scripts de patch (apply_all_patches.sh)"
    # apply_all_patches.sh takes a lift dir RELATIVE to the repo root.
    W=".kit_lift"; rm -rf "$HERE/$W"; mv "$T/lift" "$HERE/$W"
    # rc != 0 is expected: its report counts the patches the old lift shape
    # does not match (the kit delta below covers them). A missing dir is not.
    (cd "$HERE" && ./apply_all_patches.sh "$W" > "$T/patches.log" 2>&1) || true
    grep -q "^ERRO" "$T/patches.log" && { cat "$T/patches.log"; die "apply_all_patches.sh falhou"; }
    # shellcheck disable=SC2086
    stage_capture ppu_patched "$HERE/$W" $PPU_FILES
    echo "   delta do kit (kit/ppu_lift_delta.patch)"
    (cd "$HERE/$W" && patch -p1 -s < "$KIT/ppu_lift_delta.patch") || die "o delta do kit nao aplicou"
    # Kit sem Python fase 2a: where the delta's compensation of the FAILED patches lands.
    # shellcheck disable=SC2086
    stage_capture ppu_after/kit_delta "$HERE/$W" $PPU_FILES
    (cd "$HERE/$W" && shasum -a 256 -c "$KIT/ppu_lift.sha256" >/dev/null) \
        || { (cd "$HERE/$W" && shasum -a 256 -c "$KIT/ppu_lift.sha256" | grep -v ': OK'); die "o PPU recompilado nao confere com kit/ppu_lift.sha256"; }
    rm -rf "$LIFT"; mkdir -p "$LIFT"
    cp "$HERE/$W"/ppu_recomp.h "$HERE/$W"/ppu_recomp_00?.cpp "$LIFT/"
    rm -rf "$HERE/$W"
    rm -rf "$T"; trap - EXIT
    echo "   8 arquivos verificados"
fi
# shellcheck disable=SC2086
stage_capture ppu_final "$LIFT" $PPU_FILES
kit_stop_after 4

# ---- 5. SPU recompilation ---------------------------------------------------------
say "5/7 recompilacao dos SPU"
if (cd "$HERE/spu_lifted" 2>/dev/null && shasum -a 256 -c "$KIT/spu_lift.sha256" >/dev/null 2>&1) \
   && [ -f "$HERE/spu_hit_de6dc3a5ea2be487.bin" ] && [ -f "$HERE/spu_hit_2a5c4e67a14505b8.bin" ] \
   && [ -f "$HERE/spu_miss_cedb9a67a0c3a305.bin" ]; then
    echo "   spu_lifted/ ja' confere"
else
    IMAGES_DIR="$HERE" "$KIT/make_spu_lifts.sh" "$HERE/EBOOT.ELF" "$HERE/spu_lifted" "$ENGINE" "$HERE" \
        > "$HERE/spu_lifted.log" 2>&1 || { tail -20 "$HERE/spu_lifted.log"; die "a recompilacao dos SPU falhou"; }
    (cd "$HERE/spu_lifted" && shasum -a 256 -c "$KIT/spu_lift.sha256" >/dev/null) \
        || die "os SPU recompilados nao conferem com kit/spu_lift.sha256"
    echo "   7 programas SPU verificados"
fi
kit_stop_after 5

# ---- 6. engine + link -------------------------------------------------------------
say "6/7 motor e binario (alguns minutos)"
if [ ! -f "$ENGINE/build-macos/build.ninja" ]; then
    cmake -S "$ENGINE" -B "$ENGINE/build-macos" -G Ninja -DCMAKE_BUILD_TYPE=Release > "$HERE/engine_build.log" 2>&1 \
        || { tail -20 "$HERE/engine_build.log"; die "configuracao do motor falhou"; }
fi
cmake --build "$ENGINE/build-macos" -j "$JOBS" >> "$HERE/engine_build.log" 2>&1 \
    || { tail -30 "$HERE/engine_build.log"; die "compilacao do motor falhou"; }
(cd "$HERE" && PS3_ENGINE_ROOT="$ENGINE" OUT=./g2play ./build_macos.sh "$LIFT" > "$HERE/g2play_build.log" 2>&1) \
    || { tail -30 "$HERE/g2play_build.log"; die "o link do jogo falhou (log: g2play_build.log)"; }

kit_stop_after 6

# ---- 7. launcher app ------------------------------------------------------------------
say "7/7 app do launcher (GoW2 Recomp.app)"
if "$HERE/launcher/macos/build_app.sh" > "$HERE/launcher_build.log" 2>&1; then
    echo "   $HERE/GoW2 Recomp.app"
else
    tail -10 "$HERE/launcher_build.log"
    echo "   aviso: o app do launcher nao compilou (log: launcher_build.log). O jogo ja' esta' pronto: ./jogar_g2.sh"
fi

say "pronto"
echo "   Jogar:      ./jogar_g2.sh   (ou abra GoW2 Recomp.app)"
echo "   iPhone:     GoW2 Recomp.app -> iPhone -> Instalar no iPhone (veja o README)"
echo "   Binario:    $HERE/g2play"
