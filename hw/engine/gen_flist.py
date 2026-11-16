#!/usr/bin/env python3
"""Write a VCS/Genus file list for OpenTitan's AES block (and what it needs)
from the Bender.yml of the OpenTitan checkout (third_party/opentitan).

CVA6 also has a module `aes` (its Zkn unit) and a package `aes_pkg`, so the
OpenTitan AES files are copied next to <out.f> with those two names changed to
`ot_aes` and `ot_aes_pkg`. The checkout itself is not touched.

usage: gen_flist.py <opentitan_dir> <out.f>
"""
import os
import re
import sys

RENAMES = [(re.compile(r"\baes_pkg\b"), "ot_aes_pkg"),
           (re.compile(r"^module aes\b", re.M), "module ot_aes")]


def renamed_copy(src, dst_dir):
    text = open(src).read()
    for pat, new in RENAMES:
        text = pat.sub(new, text)
    dst = os.path.join(dst_dir, os.path.basename(src))
    with open(dst, "w") as fh:
        fh.write(text)
    return dst

# Groups of Bender.yml (marked by '#####' comments) we take files from, in file
# order. The "prim" group also lists Ibex, so only these folders are kept, plus
# packages (*_pkg.sv) outside lowrisc_ibex.
GROUPS = {"prim", "tlul", "prim_generic", "aes"}
KEEP_DIRS = ("hw/ip/prim/", "hw/ip/prim_generic/", "hw/ip/tlul/rtl/", "hw/ip/aes/")
# Single packages from other groups that aes.sv imports (prim_pkg is filed
# under lowrisc_ibex/dv but is the generic primitive selector).
EXTRA = {"prim_pkg.sv", "keymgr_reg_pkg.sv", "keymgr_pkg.sv", "csrng_reg_pkg.sv", "csrng_pkg.sv"}


def keep(group, f):
    name = f.split("/")[-1]
    if name in EXTRA:
        return True
    if group not in GROUPS or "lowrisc_ibex" in f:
        return False
    return f.startswith(KEEP_DIRS) or name.endswith("_pkg.sv")

ot, out = sys.argv[1], sys.argv[2]
files, group = [], None
in_target = False
for line in open(f"{ot}/Bender.yml"):
    m = re.match(r"^#{5,6}\s*(.+?)\s*$", line)
    if m:
        group, in_target = m.group(1), False
        continue
    if re.match(r"^\s*-\s*target:", line):   # test-only sub-lists: skip
        in_target = True
        continue
    m = re.match(r"^\s*-\s*(hw/\S+\.sv)\s*$", line)
    if not m or in_target:
        continue
    f = m.group(1)
    if keep(group, f):
        files.append(f)

copy_dir = os.path.join(os.path.dirname(os.path.abspath(out)), "ot_aes_rtl")
os.makedirs(copy_dir, exist_ok=True)
paths = [renamed_copy(f"{ot}/{f}", copy_dir) if f.startswith("hw/ip/aes/") else f"{ot}/{f}"
         for f in dict.fromkeys(files)]

with open(out, "w") as fh:
    fh.write(f"+incdir+{ot}/hw/ip/prim/rtl\n+incdir+{ot}/hw/ip/tlul/rtl\n")
    fh.writelines(p + "\n" for p in paths)
print(f"{len(files)} files -> {out}")
