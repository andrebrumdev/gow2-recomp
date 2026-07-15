#!/usr/bin/env python3
"""Add LR to TYDISP logs so post-WAD callers are identifiable."""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_001.cpp"
s = p.read_text(encoding="utf-8", errors="replace")
if "lr=0x%08X" in s and "[TYDISP]" in s:
    print("already has lr in TYDISP")
    raise SystemExit(0)

old = """              fprintf(stderr,"[TYDISP] type=%u -> 0x%08X desc=0x%08X raw=0x%08X w1=0x%08X w2=0x%08X r3=0x%08X\\n",
                ty, tgt, (uint32_t)ctx->gpr[4], raw, w1, w2, (uint32_t)ctx->gpr[3]); } } }"""
new = """              fprintf(stderr,"[TYDISP] type=%u -> 0x%08X desc=0x%08X raw=0x%08X w1=0x%08X w2=0x%08X r3=0x%08X lr=0x%08X\\n",
                ty, tgt, (uint32_t)ctx->gpr[4], raw, w1, w2, (uint32_t)ctx->gpr[3], (uint32_t)ctx->lr); } } }"""
if old not in s:
    # try simpler form from before enhancement
    old2 = """              fprintf(stderr,"[TYDISP] type=%u -> 0x%08X\\n", ty, tgt); } }"""
    if old2 in s:
        new2 = """              fprintf(stderr,"[TYDISP] type=%u -> 0x%08X lr=0x%08X r3=0x%08X r4=0x%08X\\n",
                ty, tgt, (uint32_t)ctx->lr, (uint32_t)ctx->gpr[3], (uint32_t)ctx->gpr[4]); } }"""
        s = s.replace(old2, new2, 1)
        p.write_text(s, encoding="utf-8", newline="\n")
        print("OK simple lr")
    else:
        raise SystemExit("needle missing")
else:
    p.write_text(s.replace(old, new, 1), encoding="utf-8", newline="\n")
    print("OK lr enhanced")
