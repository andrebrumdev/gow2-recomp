#!/usr/bin/env python3
"""metrics_report.py LOG... -- companion of run_metrics.sh. Per run -- per-run metrics over the gameplay window (aligned: first 3
consecutive [FPS] seconds with draws>=300, +10 s settle, to the end)."""
import re, statistics as st, sys, os, csv
def q(v, p):
    v = sorted(v); return v[min(len(v)-1, int(round((len(v)-1)*p)))] if v else float('nan')
def one(base):
    L = open(base + '.log', errors='replace').read().split('\n')
    fps, draws, ft, cpu, cpuf = [], [], [], [], []
    for l in L:
        if l.startswith('[FPS]'):
            fps.append(int(re.search(r'fps=(\d+)', l).group(1))); draws.append(int(re.search(r'draws=(\d+)', l).group(1)))
            ft.append(None); cpu.append(None); cpuf.append(None)
        elif l.startswith('[FRAMETIME]') and fps is not None:
            m = dict(re.findall(r'(\w+)=([\d.]+)', l)); ft.append(m) if False else None
            if fps: ft[-1] = m
        elif l.startswith('[CPUWORK]') and fps:
            m = dict(re.findall(r'(\w+)=([\d.]+)', l)); cpu[-1] = float(m['cpu_ms_s']); cpuf[-1] = float(m['cpu_ms_frame'])
    # FRAMETIME/CPUWORK print right BEFORE their [FPS] line in the same second -> shift
    ftx = [None]*len(fps); cpux=[None]*len(fps); cpufx=[None]*len(fps)
    i = -1; pend_ft = pend_cpu = None
    for l in L:
        if l.startswith('[FRAMETIME]'): pend_ft = dict(re.findall(r'(\w+)=([\d.]+)', l))
        elif l.startswith('[CPUWORK]'): pend_cpu = dict(re.findall(r'(\w+)=([\d.]+)', l))
        elif l.startswith('[FPS]'):
            i += 1; ftx[i] = pend_ft; pend_ft = None
            if pend_cpu: cpux[i] = float(pend_cpu['cpu_ms_s']); cpufx[i] = float(pend_cpu['cpu_ms_frame'])
            pend_cpu = None
    run = 0; g = None
    for k, d in enumerate(draws):
        run = run + 1 if d >= 300 else 0
        if run == 3: g = k - 2; break
    ex = open(base + '.exit').read().strip() if os.path.exists(base + '.exit') else '?'
    crash = sum(1 for l in L if l.startswith('[CRASH] =====') and 'fatal' in l)
    icb = sum(1 for l in L if 'ICALL-BAD' in l)
    if g is None:
        return dict(run=os.path.basename(base), exit=ex, crash=crash, gameplay='never')
    w = range(g + 10, len(fps))
    F = [fps[k] for k in w]; D = [draws[k] for k in w]
    FT = [ftx[k] for k in w if ftx[k] and 'p50_ms' in ftx[k]]
    C = [cpux[k] for k in w if cpux[k] is not None]; CF = [cpufx[k] for k in w if cpufx[k] is not None]
    rss, fp = [], []
    def _mb(x):
        m = re.match(r'([\d.]+)([KMG])', x or '')
        if not m: return None
        v = float(m.group(1)); return v / 1024 if m.group(2) == 'K' else v * 1024 if m.group(2) == 'G' else v
    try:
        # raw rows: the footprint is the LAST field (older CSVs had a locale comma in %cpu)
        for row in list(csv.reader(open(base + '.res.csv')))[1:]:
            if len(row) < 2 or not row[1].isdigit(): continue
            rss.append(int(row[1]))
            f = _mb(row[-1])
            if f is not None and int(row[0]) >= g + 10: fp.append(f)
    except Exception: pass
    frz = sum(1 for f in F if f <= 2)
    o100 = sum(int(x['over100']) for x in FT); o50 = sum(int(x['over50']) for x in FT)
    mins = len(F) / 60.0 or 1
    return dict(run=os.path.basename(base), exit=ex, crash=crash, gp_start_s=g, win_s=len(F),
        fps_med=st.median(F), fps_mean=round(st.mean(F), 1), fps_p10=q(F, .1), draws_med=st.median(D),
        ft_p50_med=round(st.median([float(x['p50_ms']) for x in FT]), 1) if FT else None,
        ft_p99_med=round(st.median([float(x['p99_ms']) for x in FT]), 1) if FT else None,
        ft_max=round(max(float(x['max_ms']) for x in FT), 0) if FT else None,
        hitch50_per_min=round(o50 / mins, 1), hitch100_per_min=round(o100 / mins, 1), freeze_s=frz,
        cpu_pct_med=round(st.median(C) / 10.0, 0) if C else None, cpu_ms_frame_med=round(st.median(CF), 1) if CF else None,
        rss_peak_mb=round(max(rss) / 1024) if rss else None, rss_med_mb=round(st.median(rss) / 1024) if rss else None,
        footprint_med_mb=round(st.median(fp)) if fp else None, footprint_peak_mb=round(max(fp)) if fp else None,
        icall_bad=icb)
rows = [one(b[:-4] if b.endswith('.log') else b) for b in sys.argv[1:]]
keys = []
for r in rows:
    for k in r:
        if k not in keys: keys.append(k)
print('\t'.join(keys))
for r in rows: print('\t'.join(str(r.get(k, '')) for k in keys))
