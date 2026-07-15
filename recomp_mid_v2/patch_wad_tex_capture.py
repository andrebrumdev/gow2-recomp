#!/usr/bin/env python3
"""After WADLD-T1R, capture ~texture packages via ps3_host_wad_tex_capture."""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_001.cpp"
s = p.read_text(encoding="utf-8", errors="replace")
if "ps3_host_wad_tex_capture" in s:
    print("already")
    raise SystemExit(0)

decl = 'extern "C" void ps3_host_wad_tex_capture(const char* name, uint32_t buf, uint32_t size);\n'
if '#include <math.h>\n' in s:
    s = s.replace('#include <math.h>\n', '#include <math.h>\n\n' + decl, 1)
else:
    s = decl + s

# Prefer attaching to existing T1R probe block
needle = """            fprintf(stderr,"[WADLD-T1R] #%d name='%s' result=0x%08X size=%u buf=0x%08X hit=%d\\n",
              n, nm, res, sz, buf, res!=0); fflush(stderr);"""
# file may already have the expanded probe; search for unique marker
if "[WADLD-T1R]" not in s:
    raise SystemExit("WADLD-T1R probe missing — run patch_type1_result.py first")

# Insert capture after the T1R logging block's closing of the SHGX dump if present,
# otherwise after first T1R fprintf.
marker = "fprintf(stderr,\"[WADLD-T1R]"
i = s.find(marker)
if i < 0:
    raise SystemExit("T1R fprintf not found")
# find end of the if(on){...} that contains it — look for next unique after SHGX dump
insert_after = """            if(nm[0]=='~' && buf && sz > 1024){
              ps3_host_wad_tex_capture(nm, buf, sz);
            }
"""
# Try place after SHGX dump block
shgx_end = s.find("} } }", i)
# Better: after the whole if(on) block that starts near T1R
# Find the pattern used in our session (expanded probe)
anchor = "if(nm[0]=='S'&&nm[1]=='H'&&nm[2]=='G'&&nm[3]=='X'"
j = s.find(anchor, i)
if j > 0:
    # find closing of that if and the if(on) 
    k = s.find("} } }", j)
    if k < 0:
        k = s.find("}\n          } }", j)
    if k > 0:
        # insert before the final closes of the outer scope after T1R vars
        # place right after "} }" that closes if(on) 
        # Search forward for "} }" after SHGX
        close = s.find("} }", j)
        # After SHGX inner closes we want capture still inside the outer { with nm/buf
        # Find: after `} }` that ends if(on)
        # Pattern from applied code:
        #            } }
        #            /* Host decode ...
        end_on = s.find("\n            } }", j)
        if end_on > 0:
            pos = end_on + len("\n            } }")
            s = s[:pos] + "\n" + insert_after + s[pos:]
            p.write_text(s, encoding="utf-8", newline="\n")
            print("OK wad_tex capture (after if-on)")
            raise SystemExit(0)

# Fallback: right after first T1R fprintf line's fflush
ff = s.find("fflush(stderr);", i)
if ff < 0:
    raise SystemExit("fflush after T1R not found")
pos = ff + len("fflush(stderr);")
s = s[:pos] + "\n" + insert_after + s[pos:]
p.write_text(s, encoding="utf-8", newline="\n")
print("OK wad_tex capture (fallback)")
