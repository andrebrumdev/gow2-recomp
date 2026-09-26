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


def detail_log():
    """10 gameplay seconds: 6 normal (draws 500, 34 fps), then 4 heavy (draws 950, 22 fps).
    Audio: second 3 silent with a port running, second 4 has 5 underrun frames; the
    [AUDIO] line before the window (falta=99, silent) and the one after the 10th
    gameplay second must not count."""
    out = ["[ios] guest thread started (qos requested=interactive attr=set)",
           "[ios] guest thread qos effective=interactive",
           "[spurs kernel] started: 4 worker(s), nSpus=2",
           "[IOSPERF] t=0.0 thermal=0 footprint_mb=500 available_mb=3500",
           "[FPS] fps=28 draws=120 present_ms_avg=1.00 decode_ms_avg=2.00",
           "[AUDIO] t=1.000 blocos=188 pico=0.0000 cru=0.0000 espera=0 pulados=0 perdidos=0 falta=99 anel=0 portos=1/1 mudo=0"]
    for i in range(1, 11):
        heavy = i > 6
        out.append(f"[IOSPERF] t={float(i):.1f} thermal=0 footprint_mb=500 available_mb=3500")
        out.append(f"[FIFOKICK] guest=100 wake=10 ({90.0 if heavy else 50.0:.1f}% sincrono)")
        out.append(f"[CPUWORK] cpu_ms_frame={160.0 if heavy else 100.0:.2f} cpu_ms_s=3600 frames=30 draws=900")
        out.append(f"[FPS] fps={22 if heavy else 34} draws={950 if heavy else 500} present_ms_avg=1.50 "
                   f"present_ms_max=2.00 gpu_ms=4.00 decode_ms_avg={18.5 if heavy else 11.5:.2f} giant_wait_ms=0.0")
        out.append(f"[AUDIO] t={i}.500 blocos=188 pico={0.0 if i == 3 else 0.25:.4f} cru=0.3000 espera=0 "
                   f"pulados=0 perdidos=0 falta={5 if i == 4 else 0} anel=512 portos=1/1 mudo=0")
    out.append("[RSX metal] bc decoded: gpu=3 cpu=0 resident_mb=10.5 evicted=0 dropped=0")
    return out


def detail_checks():
    bad = 0
    d = perf_report.detail(detail_log(), seconds=10, draws_min=400, heavy=800)
    bad += fails(d["qos_requested"] == "interactive" and d["qos_attr"] == "set"
                 and d["qos_effective"] == "interactive" and d["workers"] == 4, f"launch lines {d}")
    bad += fails(perf_report.env_proof(d, "interactive", 4) == [], "matching expectations -> no mismatch")
    bad += fails(len(perf_report.env_proof(d, "interactive", 6)) == 1, "workers created 4 != 6")
    refused = [l.replace("attr=set", "attr=refused").replace("effective=interactive", "effective=default")
               for l in detail_log()]
    dr = perf_report.detail(refused, seconds=10)
    bad += fails(len(perf_report.env_proof(dr, "interactive", None)) == 2, f"refused attr + wrong effective {dr}")
    old = [l for l in detail_log() if "qos effective" not in l]
    old = [l.replace("(qos requested=interactive attr=set)", "(qos=inherit)") for l in old]
    do = perf_report.detail(old, seconds=10)
    bad += fails(do["qos_requested"] == "inherit" and do["qos_attr"] is None and do["qos_effective"] is None,
                 f"pre-1c log format {do}")
    bad += fails(perf_report.env_proof(do, "inherit", None) == [], "inherit needs no attr/effective")
    bad += fails(perf_report.env_proof(do, "interactive", None) != [], "inherit run is not a QoS variant")
    bad += fails(d["heavy_seconds"] == 4 and d["heavy_fps"] == 22 and d["heavy_cpu_ms_frame"] == 160.0
                 and d["heavy_decode_ms"] == 18.5, f"heavy band {d}")
    bad += fails(d["normal_seconds"] == 6 and d["normal_fps"] == 34 and d["normal_cpu_ms_frame"] == 100.0
                 and d["normal_decode_ms"] == 11.5, f"normal band {d}")
    # the FIFOKICK line before the first gameplay second is outside the window: 5x50 + 4x90 -> median 50
    bad += fails(d["fifo_sync_pct"] == 50.0, f"fifo sync {d['fifo_sync_pct']}")
    # audio lines of gameplay seconds 1..9 only (the 10th comes after the window closed)
    bad += fails(d["audio_seconds"] == 9 and d["audio_silent_s"] == 1 and d["audio_falta"] == 5, f"audio {d}")
    bad += fails(d["bc_gpu"] == 3 and d["bc_cpu"] == 0, f"bc {d}")
    # heavy threshold is a parameter: at 1000 every second is normal
    d2 = perf_report.detail(detail_log(), seconds=10, draws_min=400, heavy=1000)
    bad += fails(d2["heavy_seconds"] == 0 and d2["heavy_fps"] is None and d2["normal_seconds"] == 10, f"heavy=1000 {d2}")
    # muted output (app inactive) is not "silent"
    muted = [l.replace("mudo=0", "mudo=1") for l in detail_log()]
    bad += fails(perf_report.detail(muted, seconds=10)["audio_silent_s"] == 0, "mudo=1 is not silence")

    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as fh:
        fh.write("\n".join(detail_log()) + "\n")
        tmp = fh.name
    p = subprocess.run([sys.executable, str(TOOL), tmp, "--seconds", "10", "--detail"], capture_output=True, text=True)
    plain = subprocess.run([sys.executable, str(TOOL), tmp, "--seconds", "10"], capture_output=True, text=True)
    ok = subprocess.run([sys.executable, str(TOOL), tmp, "--seconds", "10", "--detail",
                         "--expect-qos", "interactive", "--expect-workers", "4"], capture_output=True, text=True)
    mis = subprocess.run([sys.executable, str(TOOL), tmp, "--seconds", "10", "--expect-workers", "6"],
                         capture_output=True, text=True)
    os.unlink(tmp)
    bad += fails("| heavy (draws >= 800) seconds | 4 |" in p.stdout
                 and "| guest QoS requested (launch line) | interactive |" in p.stdout
                 and "| guest QoS effective on the thread | interactive |" in p.stdout, f"cli detail\n{p.stdout}")
    bad += fails("#### detail" not in plain.stdout, "default output must not change")
    bad += fails(ok.returncode == 2 and "| env proof | OK |" in ok.stdout, f"expect ok rc={ok.returncode}\n{ok.stdout}")
    bad += fails(mis.returncode == 3 and "MISMATCH" in mis.stdout, f"expect mismatch rc={mis.returncode}\n{mis.stdout}")
    return bad


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

    bad += detail_checks()

    print("PASS" if not bad else f"FAIL {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
