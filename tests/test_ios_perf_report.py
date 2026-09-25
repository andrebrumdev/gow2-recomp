#!/usr/bin/env python3
"""perf_report.py on synthetic logs: gameplay-only percentiles, full coverage
(900 gameplay seconds, a thermal sample every second, the first included),
missing samples counted as serious and rejected, serious/critical limits,
truncated runs, no gameplay."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent / "ios" / "perf_report.py"
sys.path.insert(0, str(TOOL.parent))
import perf_report  # noqa: E402


def log(seconds, thermal, drop_perf=()):
    """seconds: list of (fps, draws), one per wall second; thermal(i) gives the
    state at second i; drop_perf: seconds whose [IOSPERF] line is missing."""
    out = []
    for i, (f, d) in enumerate(seconds):
        if i not in drop_perf:
            out.append(f"[IOSPERF] t={float(i):.1f} thermal={thermal(i)} footprint_mb=730 available_mb=3300")
        out.append(f"[FPS] fps={f} draws={d} present_ms_avg=1.0")
    return out


MENU = [(28, 120)] * 20


def run(secs, thermal=lambda i: 0, drop=()):
    return perf_report.analyze(log(secs, thermal, drop), seconds=900, draws_min=400)


def fails(cond, msg):
    if not cond:
        print("FAIL:", msg)
    return 0 if cond else 1


def main():
    bad = 0
    r = run(MENU + [(30, 900)] * 850 + [(24, 900)] * 50)
    bad += fails(r["start"] == 20.0 and r["gameplay_seconds"] == 900, f"window {r}")
    bad += fails(r["p50"] == 30 and r["p5"] == 24, f"p50/p5 {r['p50']}/{r['p5']}")
    bad += fails(r["complete"] and not r["target_met"], "p5 24 < 25 must miss the target")

    # loading seconds inside the window are excluded from the percentiles (would be p5 12 otherwise)
    r = run(MENU + [(31, 900)] * 100 + [(12, 90)] * 60 + [(31, 900)] * 800)
    bad += fails(r["complete"] and r["other_seconds"] == 60 and r["p5"] == 31 and r["target_met"],
                 f"loading excluded {r}")
    bad += fails(r["wall_seconds"] == 960, f"wall seconds {r['wall_seconds']}")

    game = MENU + [(31, 900)] * 900
    r = run(game, lambda i: 2 if 500 <= i < 600 else 1)
    bad += fails(r["serious_s"] == 100 and r["target_met"], f"100 s serious is within 2 minutes {r}")
    r = run(game, lambda i: 2 if i == 20 else 0)
    bad += fails(r["serious_s"] == 1, "the first thermal sample of the window counts")
    r = run(game, lambda i: 2 if 300 <= i < 450 else 0)
    bad += fails(r["serious_s"] == 150 and not r["target_met"], "150 s serious misses the target")
    r = run(game, lambda i: 3 if i == 700 else 0)
    bad += fails(r["critical_s"] == 1 and not r["target_met"], "one critical second misses the target")

    r = run(game, drop=(400, 401))
    bad += fails(r["missing_thermal_s"] == 2 and r["serious_s"] == 2 and not r["complete"]
                 and not r["target_met"], f"missing samples {r}")

    r = run(MENU + [(40, 900)] * 300)
    bad += fails(not r["complete"] and not r["target_met"] and r["gameplay_seconds"] == 300, "a 300 s run is incomplete")
    r = run([(28, 120)] * 60)
    bad += fails(r["start"] is None and not r["target_met"], "no gameplay window")

    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as fh:
        fh.write("\n".join(log(game, lambda i: 0)) + "\n")
        tmp = fh.name
    p = subprocess.run([sys.executable, str(TOOL), tmp, "--label", "fixture"], capture_output=True, text=True)
    os.unlink(tmp)
    bad += fails(p.returncode == 0 and "| p50 fps (gameplay) | 31 |" in p.stdout, f"cli rc={p.returncode}\n{p.stdout}")

    print("PASS" if not bad else f"FAIL {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
