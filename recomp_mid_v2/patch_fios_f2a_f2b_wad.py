#!/usr/bin/env python3
"""FIOS F2a freelist + F2b movie_io for R_LglScA/R_PermA after MovieStop.

Measured 2026-07-21:
  F2a: media+0x16C=0 and freelist empty after MovieStop; guest CAS cannot
       pop even after re-seed. Fix: FREELIST-REBUILD at MovieStop + HOST-POP
       when op_alloc returns 0 with head!=0.
  F2b: dearchiver rejects /wad/r_lglsca.wad_ps3 (not in psarc stream).
       Fix: movie_io_open from movie_cache + fake file object + DONEFORCE.

Markers: FIOS-FREELIST-REBUILD, FIOS-HOST-POP, FIOS-F2B-MOVIEIO, FIOS-42B4-CANCEL-YIELD
Idempotent. Lift is gitignored — re-run after re-lift.

Usage: python3 recomp_mid_v2/patch_fios_f2a_f2b_wad.py [recomp_macos_v2]
"""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "recomp_macos_v2"

def main():
    print("Apply order after re-lift:")
    print("  1) patch_fios_stop_yield.py")
    print("  2) patch_fios_done_cancel_yield.py")
    print("  3) re-apply F2a/F2b host helpers from this session's lift diffs")
    print("  (see notes/2026-07-21-wad-trigger-g4.md §18)")
    print("ROOT would be", ROOT)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
