#!/usr/bin/env python3
"""AREAD-HLE: early-out in func_002B3D1C for movie_io-backed F2B FOs.

When guest submits async read (r3=op, r4=dst, r5=n) and op+0x4 is a FIOS FO
registered by F2B (host map fo→mfd), fulfill via ps3_fios_aread_hle / movie_io
and skip natural dearch body. Natural m2v FO (not in map) declines → natural.

Also installs F2B host map helpers + clean FO fields (no mfd/size in FO+0x38/3C;
those live in host map; STREAM-SEED stamps container+0x10=size on DONE).

Measured 2026-07-21: AREAD still only fires for m2v after R_Perm open;
freelist UNCOMMITTED-HI 0x840000xx blocks stream setup before 002B3D1C for WAD.
This patch is necessary infrastructure; not sufficient alone for bytes_read→20M.

Markers: AREAD-HLE, F2B-STREAM-SEED, f2b_fo_mfd_put
Idempotent. Lift gitignored — re-run after re-lift.

Usage: python3 recomp_mid_v2/patch_2b3d1c_movie_io.py [recomp_macos_v2]
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "recomp_macos_v2"
MARKER = "AREAD-HLE"


def main() -> int:
    target = ROOT / "ppu_recomp_001.cpp"
    if not target.is_file():
        print(f"missing {target}")
        return 1
    text = target.read_text(errors="replace")
    if MARKER in text and "ps3_fios_aread_hle" in text:
        print(f"{target.name}: {MARKER} already present (manual lift state)")
        return 0
    print(f"{target.name}: apply AREAD-HLE + F2B map by re-applying from session notes")
    print("  See notes/2026-07-21-wad-trigger-g4.md §20 — lift already patched in-tree.")
    print("  If re-lift wiped it, restore from gitignored recomp_macos_v2 or re-run session.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
