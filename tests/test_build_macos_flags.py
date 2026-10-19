#!/usr/bin/env python3
"""build_macos.sh: macOS deployment target + optional Vulkan.

Runs the script under fake clang/clang++ (reusing the engine's dry-run
harness, ../ps3recomp/tools/tests/test_build_macos_ios_dry_run.py) and asserts
on the logged argv. Override the engine checkout with PS3_ENGINE_ROOT.
"""
import os
import re
import sys
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
ENGINE = Path(os.environ.get("PS3_ENGINE_ROOT", HERE.parent / "ps3recomp"))
sys.path.insert(0, str(ENGINE / "tools" / "tests"))
import test_build_macos_ios_dry_run as h  # noqa: E402

SCRIPT = (HERE / "build_macos.sh").read_text()
MIN = re.compile(r"-mmacosx-version-min=(\S+)")


def run(extra_env=None):
    with tempfile.TemporaryDirectory(prefix="gow2_flags_") as tmp:
        root = Path(tmp)
        h._make_fakebin(root)
        here, lift, _p, _o = h._make_sandbox(root, SCRIPT)
        r, log = h._run_under_fakes(root, here, lift, target=None, extra_env=extra_env)
        return r, log.read_text().splitlines()


def main():
    fails = []
    r, lines = run()
    if r.returncode != 0:
        fails.append(f"default run exited {r.returncode}: {r.stderr[-1500:]}")
    else:
        cc = [l for l in lines if re.search(r"clang", l.split(" ")[0])]
        links = [l for l in cc if " -c " not in l and " -o " in l]
        comps = [l for l in cc if " -c " in l]
        if not comps or not links:
            fails.append("no compile/link lines logged")
        for l in comps + links:
            m = MIN.search(l)
            if not m or m.group(1) != "14.0":
                fails.append("missing/wrong -mmacosx-version-min=14.0: " + l[:160])

    r, lines = run({"GOW2_MACOS_MIN": "13.0"})
    if r.returncode != 0 or not any("-mmacosx-version-min=13.0" in l for l in lines):
        fails.append("GOW2_MACOS_MIN=13.0 not honoured")
    r, lines = run({"GOW2_MACOS_MIN": "13.0", "MACOSX_DEPLOYMENT_TARGET": "15.0"})
    if r.returncode != 0 or not any("-mmacosx-version-min=13.0" in l for l in lines):
        fails.append("GOW2_MACOS_MIN must win over MACOSX_DEPLOYMENT_TARGET")
    r, lines = run({"MACOSX_DEPLOYMENT_TARGET": "15.0"})
    if r.returncode != 0 or not any("-mmacosx-version-min=15.0" in l for l in lines):
        fails.append("MACOSX_DEPLOYMENT_TARGET=15.0 not honoured")

    # Vulkan gating
    if "PS3_MAC_VULKAN" not in SCRIPT:
        fails.append("PS3_MAC_VULKAN not referenced in build_macos.sh")
    else:
        # A real (Vulkan-free) archive: the gate runs nm on RUNTIME_LIB and a
        # failing nm must abort, so the harness's placeholder file cannot be used.
        with tempfile.TemporaryDirectory(prefix="gow2_novk_") as tmp:
            c = Path(tmp) / "n.c"
            c.write_text("int f(void){return 0;}\n")
            subprocess.run(["/usr/bin/clang", "-c", str(c), "-o", f"{tmp}/n.o"], check=True)
            subprocess.run(["/usr/bin/ar", "rcs", f"{tmp}/libnovk.a", f"{tmp}/n.o"], check=True)
            r, lines = run({"PS3_MAC_VULKAN": "0", "RUNTIME_LIB": f"{tmp}/libnovk.a"})
        link = [l for l in lines if " -framework Metal " in l]
        if r.returncode != 0 or not link:
            fails.append(f"PS3_MAC_VULKAN=0 run failed ({r.returncode}): {r.stderr[-800:]}")
        else:
            for tok in ("-lvulkan", "shaderc", "/opt/homebrew/lib"):
                if tok in link[0]:
                    fails.append(f"PS3_MAC_VULKAN=0 link still has {tok}")
        # Abort path: a runtime archive that references vkCreateInstance.
        with tempfile.TemporaryDirectory(prefix="gow2_vkarch_") as tmp:
            c = Path(tmp) / "v.c"
            c.write_text("extern int vkCreateInstance(void); int f(void){return vkCreateInstance();}\n")
            subprocess.run(["/usr/bin/clang", "-c", str(c), "-o", f"{tmp}/v.o"], check=True)
            subprocess.run(["/usr/bin/ar", "rcs", f"{tmp}/libvk.a", f"{tmp}/v.o"], check=True)
            r, _ = run({"PS3_MAC_VULKAN": "0", "RUNTIME_LIB": f"{tmp}/libvk.a"})
            if r.returncode == 0 or "PS3_MAC_VULKAN=0 but" not in r.stderr:
                fails.append(f"PS3_MAC_VULKAN=0 did not abort on Vulkan runtime (rc={r.returncode})")
            # The abort must come before any compile (cheap failure).
            if any(" -c " in l for l in _):
                fails.append("PS3_MAC_VULKAN=0 abort ran after compiling")
        # Invalid value aborts.
        r, _ = run({"PS3_MAC_VULKAN": "yes"})
        if r.returncode == 0 or "must be auto|0" not in r.stderr:
            fails.append(f"PS3_MAC_VULKAN=yes was accepted (rc={r.returncode})")

    if fails:
        print("FAIL")
        print("\n".join(fails))
        return 1
    print("OK: build_macos.sh flags")
    return 0


if __name__ == "__main__":
    sys.exit(main())
