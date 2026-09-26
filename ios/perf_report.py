#!/usr/bin/env python3
"""perf_report.py LOG [--seconds 200] [--draws 400] [--label NAME] [--detail] [--heavy 800] [--expect-qos NAME] [--expect-workers N]

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

--detail adds a second table over the same window: per draw band (normal:
draws..heavy-1, heavy: >= heavy) the gameplay seconds and median fps /
cpu_ms_frame / decode_ms_avg (RSX FIFO decode, not BC); audio health from
PS3_TRACE_AUDIO=1 [AUDIO] lines; the last BC decode counters; the median
FIFO synchronous share; the guest QoS as requested, as applied at thread
create and as in effect on the thread; and the SPU workers created.
--expect-qos/--expect-workers compare those launch lines with what the run
was launched with and exit 3 on any mismatch (the run is then invalid).
Exit 0: target met; 2: target missed or incomplete; 1: no gameplay window; 3: env proof mismatch (--expect-*)."""
import argparse
import math
import re
import sys

FPS = re.compile(r"\[FPS\] fps=(\d+) draws=(\d+)")
PERF = re.compile(r"\[IOSPERF\] t=([0-9.]+) thermal=(\d) footprint_mb=(\d+) available_mb=(\d+)")
THERMAL = ["nominal", "fair", "serious", "critical"]
SERIOUS = 2
CPUW = re.compile(r"\[CPUWORK\] cpu_ms_frame=([0-9.]+) cpu_ms_s=(\d+)")
DECODE = re.compile(r"decode_ms_avg=([0-9.]+)")
AUDIO = re.compile(r"\[AUDIO\] .*?pico=([0-9.]+) .*?falta=(\d+) .*?portos=(\d+)/(\d+) mudo=(\d)")
BCSTAT = re.compile(r"bc decoded: gpu=(\d+) cpu=(\d+)")
FIFOKICK = re.compile(r"\[FIFOKICK\] guest=\d+ wake=\d+ \(([0-9.]+)% sincrono\)")
QOS_OLD = re.compile(r"\[ios\] guest thread (?:started|FAILED) \(qos=([^ )]+)\)")
QOS_REQ = re.compile(r"\[ios\] guest thread (?:started|FAILED) \(qos requested=([^ )]+) attr=([^ )]+)\)")
QOS_EFF = re.compile(r"\[ios\] guest thread qos effective=(\S+)")
WORKERS = re.compile(r"\[spurs kernel\] started: (\d+) worker")


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


def detail(lines, seconds=200, draws_min=400, heavy=800):
    """Extras over the same gameplay window as analyze() (see the module doc)."""
    seen_perf = started = False
    n_gp = 0
    cpw = None                          # [CPUWORK] of the second whose [FPS] line comes next
    bands = {"normal": [], "heavy": []}  # (fps, cpu_ms_frame, decode_ms_avg)
    audio = {"seconds": 0, "silent": 0, "falta": 0}
    fifo = []
    bc = qos_req = qos_attr = qos_eff = workers = None
    for line in lines:
        if PERF.search(line):
            seen_perf = True
            continue
        m = QOS_REQ.search(line)
        if m:
            qos_req, qos_attr = m.group(1), m.group(2)
            continue
        m = QOS_OLD.search(line)
        if m:
            qos_req = m.group(1)
            continue
        m = QOS_EFF.search(line)
        if m:
            qos_eff = m.group(1)
            continue
        m = WORKERS.search(line)
        if m:
            workers = int(m.group(1))
            continue
        m = BCSTAT.search(line)
        if m:
            bc = (int(m.group(1)), int(m.group(2)))   # cumulative counters: the last line wins
            continue
        m = CPUW.search(line)
        if m:
            cpw = float(m.group(1))
            continue
        in_window = started and n_gp < seconds
        m = AUDIO.search(line)
        if m:
            if in_window:
                audio["seconds"] += 1
                running, muted = int(m.group(3)), m.group(5) == "1"
                if running > 0 and not muted and float(m.group(1)) == 0.0:
                    audio["silent"] += 1
                audio["falta"] += int(m.group(2))
            continue
        m = FIFOKICK.search(line)
        if m:
            if in_window:
                fifo.append(float(m.group(1)))
            continue
        m = FPS.search(line)
        if not m:
            continue
        f, d = int(m.group(1)), int(m.group(2))
        cpu, cpw = cpw, None
        if not seen_perf:
            continue
        if not started:
            if d < draws_min:
                continue
            started = True
        if n_gp >= seconds or d < draws_min:
            continue
        dm = DECODE.search(line)
        bands["heavy" if d >= heavy else "normal"].append((f, cpu, float(dm.group(1)) if dm else None))
        n_gp += 1

    def med(vals):
        return nearest_rank([v for v in vals if v is not None], 50)

    out = {"qos_requested": qos_req, "qos_attr": qos_attr, "qos_effective": qos_eff, "workers": workers,
           "bc_gpu": bc[0] if bc else None, "bc_cpu": bc[1] if bc else None,
           "fifo_sync_pct": med(fifo),
           "audio_seconds": audio["seconds"], "audio_silent_s": audio["silent"], "audio_falta": audio["falta"]}
    for name, rows in bands.items():
        out[f"{name}_seconds"] = len(rows)
        out[f"{name}_fps"] = med([r[0] for r in rows])
        out[f"{name}_cpu_ms_frame"] = med([r[1] for r in rows])
        out[f"{name}_decode_ms"] = med([r[2] for r in rows])
    return out


def env_proof(d, expect_qos=None, expect_workers=None):
    """What the run was launched with vs what the log shows: QoS requested, applied
    to the thread attributes at create, in effect on the thread; workers created.
    Returns the mismatches (empty list = proof OK)."""
    bad = []
    if expect_qos is not None:
        if d["qos_requested"] != expect_qos:
            bad.append(f"qos requested={d['qos_requested']} expected {expect_qos}")
        elif expect_qos != "inherit":
            if d["qos_attr"] != "set":
                bad.append(f"qos attr={d['qos_attr']} (not applied at create)")
            if d["qos_effective"] != expect_qos:
                bad.append(f"qos effective={d['qos_effective']} expected {expect_qos}")
    if expect_workers is not None and d["workers"] != expect_workers:
        bad.append(f"SPU workers created={d['workers']} expected {expect_workers}")
    return bad


def markdown_detail(d, heavy, proof=None):
    rows = [
        ("guest QoS requested (launch line)", d["qos_requested"]),
        ("guest QoS attr at create (set/refused/unknown-name/inherit)", d["qos_attr"]),
        ("guest QoS effective on the thread", d["qos_effective"]),
        ("SPU workers created (launch line)", d["workers"]),
        (f"heavy (draws >= {heavy}) seconds", d["heavy_seconds"]),
        ("heavy median fps", d["heavy_fps"]), ("heavy median cpu_ms_frame", d["heavy_cpu_ms_frame"]),
        ("heavy median decode_ms_avg (FIFO)", d["heavy_decode_ms"]),
        ("normal seconds", d["normal_seconds"]), ("normal median fps", d["normal_fps"]),
        ("normal median cpu_ms_frame", d["normal_cpu_ms_frame"]),
        ("normal median decode_ms_avg (FIFO)", d["normal_decode_ms"]),
        ("median FIFO synchronous %", d["fifo_sync_pct"]),
        ("[AUDIO] seconds in window", d["audio_seconds"]),
        ("silent seconds (port running, peak 0)", d["audio_silent_s"]),
        ("underrun frames (falta, sum)", d["audio_falta"]),
        ("BC decoded gpu / cpu (last line)", f"{d['bc_gpu']} / {d['bc_cpu']}"),
    ]
    if proof is not None:
        rows.append(("env proof", "OK" if not proof else "MISMATCH: " + "; ".join(proof)))
    out = ["#### detail", "", "| metric | value |", "|---|---|"]
    out += [f"| {k} | {v} |" for k, v in rows]
    return "\n".join(out) + "\n"


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
    ap.add_argument("--detail", action="store_true")
    ap.add_argument("--heavy", type=int, default=800)
    ap.add_argument("--expect-qos", default=None)
    ap.add_argument("--expect-workers", type=int, default=None)
    a = ap.parse_args()
    with open(a.log, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    r = analyze(lines, a.seconds, a.draws)
    if r["start"] is None:
        print(f"### {a.label}\n\nno gameplay window: no [FPS] line with draws >= {a.draws} after an [IOSPERF] line")
        return 1
    print(markdown(r, a.label, a.seconds))
    expecting = a.expect_qos is not None or a.expect_workers is not None
    proof = None
    if a.detail or expecting:
        d = detail(lines, a.seconds, a.draws, a.heavy)
        proof = env_proof(d, a.expect_qos, a.expect_workers) if expecting else None
        print(markdown_detail(d, a.heavy, proof))
    if proof:
        return 3
    return 0 if r["target_met"] else 2


if __name__ == "__main__":
    sys.exit(main())
