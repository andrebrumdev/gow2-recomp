# Minimal assertions for the kit's bash tests. Source it; call t_done at the end.
T_FAILS=0
t_eq() { # t_eq <expected> <actual> <message>
    if [ "$1" = "$2" ]; then printf '  ok   %s\n' "$3"
    else printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$3" "$1" "$2"; T_FAILS=$((T_FAILS + 1)); fi
}
t_true() { # t_true <message> <command...>
    local m=$1; shift
    if "$@"; then printf '  ok   %s\n' "$m"; else printf '  FAIL %s\n' "$m"; T_FAILS=$((T_FAILS + 1)); fi
}
t_false() {
    local m=$1; shift
    if "$@"; then printf '  FAIL %s (expected failure)\n' "$m"; T_FAILS=$((T_FAILS + 1)); else printf '  ok   %s\n' "$m"; fi
}
t_tmp() { mktemp -d "${TMPDIR:-/tmp}/kit_test.XXXXXX"; }
t_done() { [ "$T_FAILS" = 0 ] && echo "PASS $(basename "$0")" || { echo "FAIL $(basename "$0"): $T_FAILS"; exit 1; }; }
