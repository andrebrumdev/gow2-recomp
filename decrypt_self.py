#!/usr/bin/env python3
# Deprecated path: this file moved to tools/decrypt_self.py on 2026-10-02 (map: scripts/README.md).
# Thin wrapper kept so old commands, docs and other checkouts keep working; remove after 2026-12-31.
# Run: same arguments and exit code (execv). Import: re-exports the moved module.
# gow2-recomp:moved-to tools/decrypt_self.py
import os
import sys

_TARGET = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tools', 'decrypt_self.py')
if __name__ == "__main__":
    os.execv(sys.executable, [sys.executable, _TARGET] + sys.argv[1:])
else:
    import importlib.util
    _spec = importlib.util.spec_from_file_location(__name__, _TARGET)
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    globals().update({k: v for k, v in vars(_mod).items() if not k.startswith("__")})
