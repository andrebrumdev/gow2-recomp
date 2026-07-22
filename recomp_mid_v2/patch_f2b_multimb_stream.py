#!/usr/bin/env python3
"""F2B multi-MB stream refill (post-SBP hang fix) + same-class audit.

Problem (2026-07-22): after WADLD-BODY #1 SBP_general (~1.1MB) with a 256KB
ring, body steps hit avail==0 and BA9F0 YIELDs without refilling. rem/header
accounting advances while the ring stays empty/desynced → next header garbage
→ BACE8 need=0x687DD790 → freelist hang.

Same-class follow-ups (audit 2026-07-22):
  - BA9BC / BA76C also waited without ensure (plateau ~1.5MB)
  - BA9F4 bare entry (sibling of BA9F0 body wait)
  - 002E1228 / 11EC / 1290 consume without refill/clamp (siblings of 1480)
  - state=3 rem=0 at FO FULL → eof_try_complete → state=0

Fix in ppu_recomp_001/002 (lift, re-apply after re-lift):
  - f2b_stream_fill: loop until ring full or min_need met
  - f2b_stream_ensure(type_sys): refill when avail short
  - f2b_stream_eof_try_complete(type_sys): idle SM at FO EOF
  - f2b_stream_pre_consume: shared refill+clamp for ring consumers
  - ensure(+eof): BA76C, BA9BC, BAB88, BA9F0, BA9F4
  - pre_consume: 002E11EC, 002E1228, 002E1290, 002E1480

Markers: F2B multi-MB fix, F2B-STREAM-ENSURE, F2B-STREAM-CLAMP,
         F2B-STREAM-EOF-DONE, f2b_stream_pre_consume
Usage: python3 recomp_mid_v2/patch_f2b_multimb_stream.py [recomp_macos_v2]
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "recomp_macos_v2"

# Wait/dispatch sites that must call ensure (type_sys in r31)
ENSURE_FUNCS = (
    "func_002BA76C",
    "func_002BA9BC",
    "func_002BAB88",
    "func_002BA9F0",
    "func_002BA9F4",
)
# Ring consumers (r3=stream, r4=need) that must pre_consume
PRE_FUNCS = (
    "func_002E11EC",
    "func_002E1228",
    "func_002E1290",
    "func_002E1480",
)
# Produce/init — must NOT look like wait-without-refill (documented only)
PRODUCE_OR_INIT = (
    "func_002E1254",  # avail += need (producer)
    "func_002E13C8",  # ring init
    "func_002E1424",  # ring init
)


def _fn_body(text: str, name: str) -> str | None:
    m = re.search(rf"^void {name}\(ppu_context\* ctx\) \{{", text, re.M)
    if not m:
        return None
    nxt = re.search(r"^void func_", text[m.end() :], re.M)
    end = m.end() + (nxt.start() if nxt else 400)
    return text[m.start() : end]


def main() -> int:
    p1 = ROOT / "ppu_recomp_001.cpp"
    p2 = ROOT / "ppu_recomp_002.cpp"
    if not p1.is_file():
        print(f"missing {p1}")
        return 1
    s1 = p1.read_text(encoding="utf-8", errors="replace")
    s2 = p2.read_text(encoding="utf-8", errors="replace") if p2.is_file() else ""
    ok = 0
    fail = 0

    for m in (
        "F2B multi-MB fix",
        "f2b_stream_ensure",
        "f2b_stream_eof_try_complete",
        "f2b_stream_pre_consume",
        "F2B-STREAM-ENSURE",
        "F2B-STREAM-CLAMP",
        "F2B-STREAM-EOF-DONE",
        "Always top-up",
    ):
        if m in s1:
            print(f"001: {m} present")
            ok += 1
        else:
            print(f"001: {m} MISSING")
            fail += 1

    combined = s1 + "\n" + s2
    for name in ENSURE_FUNCS:
        body = _fn_body(combined, name)
        if body is None:
            print(f"ENSURE {name}: MISSING fn")
            fail += 1
            continue
        has = "f2b_stream_ensure" in body
        print(f"ENSURE {name}: {'ok' if has else 'MISSING'}")
        if has:
            ok += 1
        else:
            fail += 1

    for name in PRE_FUNCS:
        body = _fn_body(s1, name)
        if body is None:
            print(f"PRE {name}: MISSING fn")
            fail += 1
            continue
        has = "f2b_stream_pre_consume" in body
        print(f"PRE {name}: {'ok' if has else 'MISSING'}")
        if has:
            ok += 1
        else:
            fail += 1

    # BA9F0 + BA9F4 should also eof-complete (body wait at FO end)
    for name in ("func_002BA9F0", "func_002BA9F4", "func_002BA76C", "func_002BAB88"):
        body = _fn_body(combined, name)
        if body and "f2b_stream_eof_try_complete" in body:
            print(f"EOF {name}: ok")
            ok += 1
        else:
            print(f"EOF {name}: MISSING")
            fail += 1

    for name in PRODUCE_OR_INIT:
        body = _fn_body(s1, name)
        if body is None:
            print(f"DOC {name}: fn missing (ok if re-lift renamed)")
            continue
        if "f2b_stream_pre_consume" in body:
            print(f"DOC {name}: unexpectedly has pre_consume (produce/init?)")
        else:
            print(f"DOC {name}: produce/init — no pre_consume (expected)")

    print(f"score ok={ok} fail={fail}")
    return 0 if fail == 0 and ok >= 12 else 2


if __name__ == "__main__":
    raise SystemExit(main())
