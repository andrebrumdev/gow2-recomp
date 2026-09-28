# kit/lib/release_guards.sh -- make_release.sh's refusals, sourced (kit/tests cover them).
#
# Each guard lists what it found on stdout and returns 0 when something is
# found. The matches are captured in full before testing: a `... | grep -q`
# under `set -o pipefail` fails open, because grep -q exits on the first match,
# the producer dies of SIGPIPE, and the pipeline reports false.

# Game files the kit must never carry (hits listed).
kit_find_game_files() { # kit_find_game_files <dir>
    local hits
    hits="$(find "$1" \( -iname 'EBOOT.*' -o -iname '*.psarc' -o -iname '*.self' -o -iname '*.m2v' \
        -o -iname '*.wad_ps3' -o -iname '*.wav' -o -iname 'spu_hit_*' -o -iname 'spu_miss_*' \) -print)" \
        || return 0   # find failed: refuse rather than pass
    [ -n "$hits" ] && printf '%s\n' "$hits"
}

# Prebuilt Mach-O files (the kit ships source only; `file` lines listed).
kit_find_macho() { # kit_find_macho <dir>
    local out hits
    out="$(find "$1" -type f -exec file {} +)" || return 0   # scan failed: refuse
    hits="$(printf '%s\n' "$out" | grep 'Mach-O' || true)"
    [ -n "$hits" ] && printf '%s\n' "$hits"
}
