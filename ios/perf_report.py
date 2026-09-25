#!/usr/bin/env python3
"""perf_report.py LOG [--seconds 200] [--draws 400] [--label NAME]

Milestone analysis for an iOS run (spec 2026-09-24, resolution 7). LOG is
Documents/gow2.log of a run with PS3_TRACE_FPS=1 and PS3_IOS_PERF_LOG=1.

- A gameplay second is an [FPS] line with draws >= --draws; menus, loading
  and cutscene seconds draw fewer and are excluded from the percentiles.
- The window starts at the [IOSPERF] second of the first gameplay [FPS] line
  and ends at the --seconds-th gameplay second. p50/p5 are nearest-rank over
  the fps of those gameplay seconds only.
- Thermal: every [IOSPERF] sample in the window counts, the first one
  included. A missing sample (a gap > 1 s between samples) counts as
  "serious" and makes the run incomplete.
- Complete = --seconds gameplay seconds AND no missing thermal sample.
  An incomplete run never meets the target.
Exit 0: target met; 2: target missed or incomplete; 1: no gameplay window."""
import argparse
import math
import re
import sys

FPS = re.compile(r"\[FPS\] fps=(\d+) draws=(\d+)")
PERF = re.compile(r"\[IOSPERF\] t=([0-9.]+) thermal=(\d) footprint_mb=(\d+) available_mb=(\d+)")
THERMAL = ["nominal", "fair", "serious", "critical"]
SERIOUS = 2


def nearest_rank(values, p):
    if not values:
        return None
    s = sorted(values)
    return s[max(1, math.ceil(p / 100.0 * len(s))) - 1]


def analyze(lines, seconds=200, draws_min=400):
    cur = None                    # the latest [IOSPERF] sample: (t, thermal, footprint, available)
    start = last_t = None
    gp, thermal, foot, avail = [], [], [], []
    missing = other = 0

    def take(sample):
        nonlocal last_t, missing
        t = sample[0]
        if last_t is not None:
            gap = int(round(t - last_t)) - 1
            if gap > 0:
                missing += gap
                thermal.extend([SERIOUS] * gap)   # conservative: an unseen second is "serious"
        thermal.append(sample[1])
        foot.append(sample[2])
        avail.append(sample[3])
        last_t = t

    for line in lines:
        m = PERF.search(line)
        if m:
            cur = (float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
            if start is not None and len(gp) < seconds:
                take(cur)
            continue
        m = FPS.search(line)
        if not m or cur is None:
            continue
        f, d = int(m.group(1)), int(m.group(2))
        if start is None:
            if d < draws_min:
                continue
            start = cur[0]
            take(cur)                              # the window's first thermal sample counts
        if len(gp) >= seconds:
            continue
        if d >= draws_min:
            gp.append(f)
        else:
            other += 1
    complete = start is not None and len(gp) == seconds and missing == 0
    serious = sum(1 for x in thermal if x == SERIOUS)
    critical = sum(1 for x in thermal if x == 3)
    p50, p5 = nearest_rank(gp, 50), nearest_rank(gp, 5)
    target = bool(complete and p50 >= 30 and p5 >= 25 and critical == 0 and serious <= 120)
    return {
        "start": start, "gameplay_seconds": len(gp), "other_seconds": other,
        "wall_seconds": (last_t - start + 1) if start is not None else 0,
        "missing_thermal_s": missing, "complete": complete,
        "p50": p50, "p5": p5,
        "serious_s": serious, "critical_s": critical,
        "max_thermal": THERMAL[max(thermal)] if thermal else None,
        "peak_footprint_mb": max(foot) if foot else None,
        "min_available_mb": min(avail) if avail else None,
        "target_met": target,
    }


def markdown(r, label, seconds):
    rows = [
        ("window start (s since launch)", r["start"]),
        ("gameplay seconds", f"{r['gameplay_seconds']} of {seconds}" + ("" if r["complete"] else " (INCOMPLETE)")),
        ("non-gameplay seconds inside the window (excluded)", r["other_seconds"]),
        ("wall seconds of the window", r["wall_seconds"]),
        ("missing thermal samples", r["missing_thermal_s"]),
        ("p50 fps (gameplay)", r["p50"]), ("p5 fps (gameplay)", r["p5"]),
        ("time at 'serious' (s)", r["serious_s"]), ("time at 'critical' (s)", r["critical_s"]),
        ("worst thermal state", r["max_thermal"]),
        ("peak footprint (MB)", r["peak_footprint_mb"]), ("min available (MB)", r["min_available_mb"]),
        ("target met (complete, p50>=30, p5>=25, no critical, serious<=120 s)", "YES" if r["target_met"] else "NO"),
    ]
    out = [f"### {label}", "", "| metric | value |", "|---|---|"]
    out += [f"| {k} | {v} |" for k, v in rows]
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--seconds", type=int, default=200)
    ap.add_argument("--draws", type=int, default=400)
    ap.add_argument("--label", default="run")
    a = ap.parse_args()
    with open(a.log, encoding="utf-8", errors="replace") as f:
        r = analyze(f, a.seconds, a.draws)
    if r["start"] is None:
        print(f"### {a.label}\n\nno gameplay window: no [FPS] line with draws >= {a.draws} after an [IOSPERF] line")
        return 1
    print(markdown(r, a.label, a.seconds))
    return 0 if r["target_met"] else 2


if __name__ == "__main__":
    sys.exit(main())
