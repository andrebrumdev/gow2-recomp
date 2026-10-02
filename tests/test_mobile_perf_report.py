#!/usr/bin/env python3
"""perf_report.py with the Android tag: [ANDPERF] windows, thermal source handling,
configurable targets, and the default tag ignoring Android lines."""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ios"))
import perf_report  # noqa: E402

fails = 0


def check(cond, msg):
    global fails
    if not cond:
        print("FAIL:", msg)
        fails += 1


def alog(seconds, src="athermal", thermal=lambda i: 0):
    out = []
    for i, (f, d) in enumerate(seconds):
        s = f" thermal_src={src}" if src else ""
        out.append(f"[ANDPERF] t={float(i):.1f} thermal={thermal(i)} footprint_mb=900 available_mb=3000{s} "
                   f"flips=30 fps={f} cpu_mhz=2400,2400")
        out.append(f"[FPS] fps={f} draws={d} present_ms_avg=1.0")
    return out


RUN = [(32, 600)] * 200

# 1. the default (iOS) tag does not see Android sample lines: no window
r = perf_report.analyze(alog(RUN), seconds=200)
check(r["start"] is None, "default tag must ignore [ANDPERF] lines")

# 2. Android tag: complete 200 s window, p50/p5, target with the default 30/25
r = perf_report.analyze(alog(RUN), seconds=200, tag="ANDPERF")
check(r["complete"] and r["p50"] == 32 and r["p5"] == 32, f"android window: {r}")
check(r["target_met"], "32/32 fps meets 30/25")
check(r["thermal_src"] == ["athermal"], f"thermal_src: {r['thermal_src']}")

# 3. configurable targets
r = perf_report.analyze(alog(RUN), seconds=200, tag="ANDPERF", p50_min=40, p5_min=25)
check(not r["target_met"], "p50 32 < 40 must miss")

# 4. thermal known and bad: 130 serious seconds fail the target
r = perf_report.analyze(alog(RUN, thermal=lambda i: 2 if i < 130 else 0), seconds=200, tag="ANDPERF")
check(r["serious_s"] == 130 and not r["target_met"], f"serious limit: {r}")

# 5. thermal source none: thermal cannot fail the run, and the report says so
r = perf_report.analyze(alog(RUN, src="none", thermal=lambda i: 2), seconds=200, tag="ANDPERF")
check(r["target_met"], "unverified thermal must not fail the run")
check(r["thermal_src"] == ["none"], f"thermal_src none: {r['thermal_src']}")
check("unverified" in perf_report.markdown(r, "x", 200), "markdown must flag unverified thermal")

# 6. a line without thermal_src (older sampler) reads as native, i.e. verified (iOS lines look like this)
r = perf_report.analyze(alog(RUN, src=None, thermal=lambda i: 2 if i < 130 else 0), seconds=200, tag="ANDPERF")
check(r["thermal_src"] == ["native"] and not r["target_met"], f"native src: {r}")

print("test_mobile_perf_report: FAIL" if fails else "test_mobile_perf_report: PASS")
sys.exit(1 if fails else 0)
