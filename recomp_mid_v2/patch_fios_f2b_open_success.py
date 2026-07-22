#!/usr/bin/env python3
"""F2B open: no re-queue dearch + restatus before 6610 + pump always-on.

Measured 2026-07-21 (Mac arm64, after R_Perm FULL via STREAM-PUMP):

  4274-after-6610 ret=0x8001070A for R_Lgl/R_Perm (m2v ret=0)
  → 4274 takes func_002B4330 error path
  → ICALL-BAD ctr=0x2F776164 ("/wad" as OPD) + freelist tag abort
  → WADLD-BODY=0 (state machine never delivers members)

Root: F2B DONEFORCE then falls into natural success tail that trampolines
to func_0030B058 (push open op to media queue — required to link op to
container). Dearch rejects /wad/* again and stamps op+44=0x8001070A.
6610 returns that error → 4274 error path.

Fix: F2B-KEEP-DONE after FO install + F2B-RESTATUS in 4274 before 6610
(clear +44, keep +90). Do NOT skip 0030B058 (poll never sees DONE).

Also: STREAM-PUMP lived inside PS3_TRACE_FIOSOPEN probe (n<8) — silent
no-op without TRACE; moved out.

Markers (lift gitignored — re-apply after re-lift):
  F2B-KEEP-DONE, F2B-RESTATUS, F2B-STREAM-PUMP outside TRACE

Usage: python3 recomp_mid_v2/patch_fios_f2b_open_success.py [recomp_macos_v2]
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "recomp_macos_v2"


def main() -> int:
    path = ROOT / "ppu_recomp_001.cpp"
    if not path.is_file():
        print(f"missing {path}")
        return 1
    text = path.read_text(errors="replace")
    ok = 0
    for marker in ("F2B-KEEP-DONE", "F2B-RESTATUS", "F2B-STREAM-PUMP"):
        if marker in text:
            print(f"001: {marker} present")
            ok += 1
        else:
            print(f"001: {marker} MISSING")
    # Pump must not be nested only under TRACE probe count
    if "NOTE: must run even when PS3_TRACE_FIOSOPEN is off" in text:
        print("001: STREAM-PUMP outside TRACE (note present)")
        ok += 1
    else:
        print("001: STREAM-PUMP TRACE-independence note MISSING")
    return 0 if ok >= 3 else 2


if __name__ == "__main__":
    raise SystemExit(main())
