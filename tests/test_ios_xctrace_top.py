#!/usr/bin/env python3
"""xctrace_top.py on a synthetic time-profile export: id/ref resolution, thread
grouping (hex tid stripped, SPU workers merged), leaf buckets, cores, and loud
failures on an empty export, a wrong schema and too many unusable rows."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent / "ios" / "xctrace_top.py"
sys.path.insert(0, str(TOOL.parent))
import xctrace_top  # noqa: E402

XML = """<?xml version="1.0"?>
<trace-query-result><node><schema name="time-profile"/>
<row><sample-time>1</sample-time><thread id="1" fmt="guest-main 0x10 (GoW2, pid: 5)"/><core id="2" fmt="CPU 0 (P Core)"/><weight id="3">1000000</weight><backtrace id="4"><frame id="5" name="func_002ACBE8"/><frame id="6" name="guest_main"/></backtrace></row>
<row><sample-time>2</sample-time><thread ref="1"/><core ref="2"/><weight ref="3"/><backtrace ref="4"/></row>
<row><sample-time>3</sample-time><thread ref="1"/><core ref="2"/><weight ref="3"/><backtrace id="7"><frame id="8" name="vm_read32"/><frame ref="5"/><frame ref="6"/></backtrace></row>
<row><sample-time>4</sample-time><thread id="9" fmt="host:spurs-worker 0x20 (GoW2, pid: 5)"/><core id="10" fmt="CPU 3 (E Core)"/><weight ref="3"/><backtrace id="11"><frame id="12" name="spu0_spu_func_0000EAF8"/><frame id="13" name="kernel_thread_main"/></backtrace></row>
<row><sample-time>5</sample-time><thread id="14" fmt="host:spurs-worker 0x21 (GoW2, pid: 5)"/><core ref="10"/><weight ref="3"/><backtrace id="15"><frame id="16" name="__psynch_cvwait"/><frame ref="13"/></backtrace></row>
</node></trace-query-result>
"""


def fails(cond, msg):
    if not cond:
        print("FAIL:", msg)
    return 0 if cond else 1


def main():
    bad = 0
    bad += fails(xctrace_top.bucket_of("func_002ACBE8") == "guest-lift", "guest lift")
    bad += fails(xctrace_top.bucket_of("func_002ACBE8(ppu_context*)") == "guest-lift", "demangled guest lift")
    bad += fails(xctrace_top.bucket_of("spu0_spu_func_0000EAF8") == "spu", "spu lift is not guest-lift")
    bad += fails(xctrace_top.bucket_of("vm_write32") == "vm-accessor", "vm accessor")
    bad += fails(xctrace_top.bucket_of("_tlv_get_addr") == "tls-trampoline", "tls")
    bad += fails(xctrace_top.bucket_of("metal_bc_cpu_decode") == "bc-decode", "bc before fifo")
    bad += fails(xctrace_top.bucket_of("metal_va_fill") == "fifo-decode", "fifo")
    bad += fails(xctrace_top.bucket_of("__psynch_cvwait") == "wait", "wait")
    bad += fails(xctrace_top.bucket_of("memcpy") == "other", "other")

    with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as fh:
        fh.write(XML)
        tmp = fh.name
    s, meta = xctrace_top.summarize(tmp)
    bad += fails(meta == {"schema": ["time-profile"], "rows": 5, "used": 5, "dropped": 0, "invalid_weight": 0}, f"meta {meta}")
    g = s.get("guest-main")
    bad += fails(g is not None and g["weight"] == 3_000_000 and g["threads"] == 1, f"guest-main {g}")
    bad += fails(g and g["bucket"]["guest-lift"] == 2_000_000 and g["bucket"]["vm-accessor"] == 1_000_000, f"buckets {g}")
    bad += fails(g and g["core"]["CPU 0 (P Core)"] == 3_000_000 and g["root"]["guest_main"] == 3_000_000, f"core/root {g}")
    w = s.get("host:spurs-worker")
    bad += fails(w is not None and w["threads"] == 2 and w["weight"] == 2_000_000
                 and w["bucket"]["spu"] == 1_000_000 and w["bucket"]["wait"] == 1_000_000, f"workers {w}")
    p = subprocess.run([sys.executable, str(TOOL), tmp], capture_output=True, text=True)
    bad += fails(p.returncode == 0 and "| guest-main | 1 | 60.0 |" in p.stdout
                 and "rows=5 used=5 dropped=0 invalid_weight=0" in p.stdout, f"cli\n{p.stdout}")
    os.unlink(tmp)

    def run_xml(text):
        with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as fh:
            fh.write(text)
            path = fh.name
        r = subprocess.run([sys.executable, str(TOOL), path], capture_output=True, text=True)
        s2, m2 = xctrace_top.summarize(path)
        os.unlink(path)
        return r, m2

    p, m = run_xml('<?xml version="1.0"?><trace-query-result><node><schema name="time-profile"/></node></trace-query-result>')
    bad += fails(p.returncode == 1 and "zero usable rows" in p.stdout and m["rows"] == 0, f"empty export must fail loudly\n{p.stdout}")
    p, m = run_xml(XML.replace('schema name="time-profile"', 'schema name="cpu-profile"'))
    bad += fails(p.returncode == 1 and "unexpected schema" in p.stdout and m["schema"] == ["cpu-profile"],
                 f"wrong schema must fail\n{p.stdout}")
    bad_rows = XML.replace("</node>",
        '<row><sample-time>6</sample-time><thread ref="1"/><core ref="2"/><weight ref="3"/></row>'
        '<row><sample-time>7</sample-time><thread ref="1"/><core ref="2"/><weight id="20">abc</weight><backtrace ref="4"/></row>'
        "</node>")
    p, m = run_xml(bad_rows)
    bad += fails(m["rows"] == 7 and m["used"] == 5 and m["dropped"] == 1 and m["invalid_weight"] == 1, f"counts {m}")
    bad += fails(p.returncode == 1 and "unusable" in p.stdout, f"2 of 7 rows unusable must fail\n{p.stdout}")

    print("PASS" if not bad else f"FAIL {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
