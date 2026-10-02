# kit/lib/pick_python.sh -- which Python the kit's remaining Python tools run on.
# Order: $PY (must qualify), a Python this kit already compiled from source
# (<gow2_root>/.kit_tools/python), then the usual names. Minimum 3.11 (tomllib in
# the PPU lifter). rc 1 = none found: setup.sh then compiles the kit's CPython source.
kit_py_ok() { "$1" -c 'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; }
kit_pick_python() {
    local root=$1 c p
    if [ -n "${PY:-}" ]; then
        kit_py_ok "$PY" && { printf '%s\n' "$PY"; return 0; }
        echo "PY=$PY is not a Python >= 3.11" >&2
        return 2
    fi
    if [ -x "$root/.kit_tools/python/bin/python3" ] && kit_py_ok "$root/.kit_tools/python/bin/python3"; then
        printf '%s\n' "$root/.kit_tools/python/bin/python3"; return 0
    fi
    for c in ${KIT_PY_CANDIDATES:-python3.14 python3.13 python3.12 python3.11 /opt/homebrew/bin/python3 python3}; do
        p="$(command -v "$c" 2>/dev/null)" || continue
        kit_py_ok "$p" && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}
