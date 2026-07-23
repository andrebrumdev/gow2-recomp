#!/usr/bin/env python3
"""Offline: same env parse helper used by patch_type15_cc9d0_disc.py.

PS3_TRACE_CC9D0 / PS3_TYPE15_DISC must treat unset, empty, and "0" as OFF.
"""
from typing import Optional


def env_on(name: str, raw: Optional[str]) -> bool:
    """Return True only for a non-empty truthy env value (not 0/false/off/no)."""
    del name  # name is for call-site clarity only
    if raw is None:
        return False
    v = raw.strip().lower()
    return v not in ("", "0", "false", "off", "no")


assert env_on("PS3_TRACE_CC9D0", None) is False
assert env_on("PS3_TRACE_CC9D0", "0") is False
assert env_on("PS3_TRACE_CC9D0", "") is False
assert env_on("PS3_TRACE_CC9D0", "false") is False
assert env_on("PS3_TRACE_CC9D0", "1") is True
assert env_on("PS3_TYPE15_DISC", None) is False
assert env_on("PS3_TYPE15_DISC", "0") is False
assert env_on("PS3_TYPE15_DISC", "1") is True

print("test_trace_cc9d0_env: PASS")
