#!/usr/bin/env python3
"""Expand CVA6's core/Flist.cva6 into a plain source list for Genus.

    cva6_files.py <cva6_dir> <config_pkg.sv> <out_files.txt>

Prints the include folders. Left out: the cache SRAM model (tc_sram stays a
black box, so cache memories are not counted as logic) and the simulation-only
instruction tracer.
"""
import os
import re
import sys

cva6, cfg_pkg, out = sys.argv[1:4]
env = {"CVA6_REPO_DIR": cva6, "HPDCACHE_DIR": f"{cva6}/core/cache_subsystem/hpdcache",
       "TARGET_CFG": "cv64a6_imafdc_sv39"}
SKIP = ("tc_sram.sv", "instr_tracer.sv")
files, incdirs = [], []


def expand(path):
    for line in open(path):
        line = re.sub(r"\$\{(\w+)\}", lambda m: env[m.group(1)], line.split("//")[0].strip())
        if not line:
            continue
        if line.startswith("+incdir+"):
            incdirs.append(line[len("+incdir+"):])
        elif line.startswith("-F"):
            expand(line[2:].strip())
        elif line.endswith("_config_pkg.sv") and "/core/include/cv" in line:
            files.append(cfg_pkg)                     # the chosen CVA6 configuration
        elif not line.endswith(SKIP):
            files.append(line)


expand(f"{cva6}/core/Flist.cva6")
with open(out, "w") as fh:
    fh.write("\n".join(files) + "\n")
print(" ".join(os.path.normpath(d) for d in incdirs))
