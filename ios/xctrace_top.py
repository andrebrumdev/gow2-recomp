#!/usr/bin/env python3
"""xctrace_top.py TP_XML [--top 20]

Summarises a Time Profiler table exported with
  xcrun xctrace export --input T.trace \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' --output tp.xml
Per thread name (hex tid stripped, so the SPURS workers merge): share of the
process samples, bucket shares of the leaf frame (what the CPU was executing),
the cores it ran on, and the top leaf symbols. Attribute by thread, not by leaf
(Mac lesson: a leaf-only read hid that guest-main runs lifted PPU code ~100%).
Exit 1 on an unexpected schema, zero usable rows, or more than 5 % of rows
dropped (no thread / backtrace / frames) or with an invalid weight: a broken
export must never read as "no hotspot". The counts are always printed."""
import argparse
import collections
import re
import sys
import xml.etree.ElementTree as ET

BUCKETS = [   # first match wins: order matters (bc before fifo, spu before guest-lift)
    ("tls-trampoline", re.compile(r"tlv_get_addr|ZTW15g_trampoline_fn|g_trampoline_fn")),
    ("vm-accessor", re.compile(r"^_*(vm_(read|write)|ppu_rsv_on_store|ps3_vm_)")),
    ("bc-decode", re.compile(r"bc_(gpu|cpu)_decode|^_*metal_bc_|^_*rsx_bc_")),
    ("fifo-decode", re.compile(r"^_*(rsx_|metal_|gcm_|cellGcm)")),
    ("spu", re.compile(r"^_*spu|^_*SPU")),
    ("guest-lift", re.compile(r"\bfunc_[0-9A-Fa-f]{8}")),
    ("wait", re.compile(r"psynch|semwait|usleep|nanosleep|mach_msg|workq_kernreturn|__ulock")),
]
TID = re.compile(r"\s+0x[0-9a-fA-F]+.*$")


def bucket_of(symbol):
    for name, rx in BUCKETS:
        if rx.search(symbol or ""):
            return name
    return "other"


def summarize(path):
    root = ET.parse(path).getroot()
    schemas = [s.get("name") for s in root.iter("schema")]
    meta = {"schema": schemas, "rows": 0, "used": 0, "dropped": 0, "invalid_weight": 0}
    if schemas != ["time-profile"]:
        return {}, meta
    ids = {e.get("id"): e for e in root.iter() if e.get("id") is not None}

    def res(e):
        if e is None:
            return None
        r = e.get("ref")
        return ids.get(r) if r is not None else e

    out = {}
    tids = collections.defaultdict(set)
    for row in root.iter("row"):
        meta["rows"] += 1
        th = res(row.find("thread"))
        bt = res(row.find("backtrace"))
        frames = [res(f) for f in bt.findall("frame")] if bt is not None else []
        frames = [f for f in frames if f is not None]
        if th is None or not frames:
            meta["dropped"] += 1
            continue
        w_el = res(row.find("weight"))
        try:
            w = int((w_el.text or "").strip())
        except (AttributeError, ValueError):
            w = 0
        if w <= 0:
            meta["invalid_weight"] += 1
            continue
        meta["used"] += 1
        fmt = th.get("fmt") or "?"
        name = TID.sub("", fmt)
        leaf = frames[0].get("name", "?")
        root_fn = frames[-1].get("name", "?")
        core_el = res(row.find("core"))
        core = core_el.get("fmt", "?") if core_el is not None else "?"
        s = out.setdefault(name, {"weight": 0, "threads": 0, "leaf": collections.Counter(),
                                  "bucket": collections.Counter(), "core": collections.Counter(),
                                  "root": collections.Counter()})
        s["weight"] += w
        s["leaf"][leaf] += w
        s["bucket"][bucket_of(leaf)] += w
        s["core"][core] += w
        s["root"][root_fn] += w
        tids[name].add(fmt)
    for name, s in out.items():
        s["threads"] = len(tids[name])
    return out, meta


def markdown(s, top):
    total = sum(v["weight"] for v in s.values()) or 1
    order = sorted(s.items(), key=lambda kv: -kv[1]["weight"])
    out = ["| thread | threads | % of process | top buckets (% of thread) | cores | root |", "|---|---|---|---|---|---|"]
    for name, v in order:
        tw = v["weight"] or 1
        b = ", ".join(f"{k} {100.0 * x / tw:.0f}" for k, x in v["bucket"].most_common(4))
        c = ", ".join(f"{k} {100.0 * x / tw:.0f}" for k, x in v["core"].most_common(3))
        r = v["root"].most_common(1)[0][0]
        out.append(f"| {name} | {v['threads']} | {100.0 * v['weight'] / total:.1f} | {b} | {c} | {r} |")
    for name, v in order[:6]:
        tw = v["weight"] or 1
        out += ["", f"#### {name}: top {top} leaf symbols", "", "| % of thread | symbol |", "|---|---|"]
        out += [f"| {100.0 * x / tw:.1f} | `{k}` |" for k, x in v["leaf"].most_common(top)]
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xml")
    ap.add_argument("--top", type=int, default=20)
    a = ap.parse_args()
    s, meta = summarize(a.xml)
    print(f"rows={meta['rows']} used={meta['used']} dropped={meta['dropped']} "
          f"invalid_weight={meta['invalid_weight']} schema={meta['schema']}")
    if meta["schema"] != ["time-profile"]:
        print('unexpected schema: expected exactly one <schema name="time-profile"> (check the xpath / Xcode version)')
        return 1
    if meta["used"] == 0:
        print("zero usable rows: the export has no usable time-profile rows (check the xpath / symbolication)")
        return 1
    if meta["dropped"] + meta["invalid_weight"] > 0.05 * meta["rows"]:
        print("more than 5% of rows unusable (dropped or invalid weight): fix the export/parser before reading the profile")
        return 1
    print(markdown(s, a.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
