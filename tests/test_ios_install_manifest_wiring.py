#!/usr/bin/env python3
"""Guard (P3 Task 2): the iOS host decides "Jogo não instalado" from the
launcher's install manifest in the container's Documents
(gow2_ios_install_state), not from P1's heuristic (EBOOT + any USRDIR file);
the old lifecycle helper is gone so nobody calls it by mistake; the host logs
the data state when it changes."""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parent / "ios" / "Sources"


def strip(t):
    t = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), t, flags=re.S)
    return re.sub(r"//[^\n]*", "", t)


def body(text, signature):
    m = re.search(signature + r"\s*\{", text)
    if not m:
        return None
    depth, i = 1, m.end()
    while depth and i < len(text):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
    return text[m.end():i - 1]


def main():
    fails = []
    host = strip((SRC / "gow2_ios_host.m").read_text(encoding="utf-8"))
    lh = strip((SRC / "gow2_ios_lifecycle.h").read_text(encoding="utf-8"))
    lc = strip((SRC / "gow2_ios_lifecycle.c").read_text(encoding="utf-8"))
    if '#include "gow2_ios_install_manifest.h"' not in host:
        fails.append("gow2_ios_host.m must include gow2_ios_install_manifest.h")
    ps = body(host, r"static void publish_status\(void\)")
    if ps is None or "gow2_ios_install_state(gow2_ios_documents()" not in ps:
        fails.append("publish_status must read the install manifest in Documents")
    elif "GOW2_INSTALL_OK" not in ps or "[ios] game data:" not in ps:
        fails.append("publish_status must publish state == GOW2_INSTALL_OK and log '[ios] game data:' on change")
    if re.search(r"gow2_ios_game_data_present\(\s*getenv", host):
        fails.append("P1's heuristic (GOW2_EBOOT / PS3_VFS_ROOT) must not decide the data state")
    if "gow2_ios_game_data_present" in lh or "gow2_ios_game_data_present" in lc:
        fails.append("the lifecycle must not keep the old helper")
    for f in fails:
        print("FAIL:", f)
    print("test_ios_install_manifest_wiring:", "FAIL" if fails else "PASS")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
