#!/usr/bin/env python3
"""Collect the AES comparison numbers into one table and two charts.

Inputs (made by scripts/cva6_sim.sh, scripts/synth.sh, scripts/power.sh):
  experiments/e1_cost/results/cva6_vcs_sw_zkne_ot.txt   cycle counts on CVA6
  build/synth/<design>/{qor,gates,timing}.rpt           Genus, 65 nm
  build/power/<design>_<run>/power_hier.rpt + build/power/<run>.saif   Joules
Outputs in experiments/e1_cost/results/:
  summary.md, cycles_per_block.png, area.png

usage: report.py   (run from anywhere; paths are relative to the repo)
"""
import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parents[3]
RES = REPO / "experiments/e1_cost/results"
SYN = REPO / "build/synth"
PWR = REPO / "build/power"
KGE_UM2 = 1440.0          # 1000 x ND2D1 (1.44 um^2) in tcbn65lp
F_NOMINAL_HZ = 500e6      # clock used to turn leakage power into energy
BLOCKS_DIFF = 255         # 4096 B run minus 16 B run

NAMES = {"sw": "Software (T-table)", "zkne": "Zkne instructions", "ot": "OpenTitan AES accelerator"}


def cycles():
    """{impl: {bytes: cycles}} plus key setup as bytes=0."""
    out = {}
    for line in (RES / "cva6_vcs_sw_zkne_ot.txt").read_text().splitlines():
        m = re.match(r"RESULT (\w+) (\w+) bytes=(\d+) cycles=(\d+)", line)
        if m:
            impl, _, nbytes, cyc = m.groups()
            out.setdefault(impl, {})[int(nbytes)] = int(cyc)
    return out


def synth(design):
    """Area (um^2), sequential area, clock target and worst slack (ns) of one Genus run."""
    d = SYN / design
    if not (d / "qor.rpt").exists():
        return None
    qor = (d / "qor.rpt").read_text()
    area = float(re.search(r"Cell Area\s+([\d.]+)", qor).group(1))
    seq = float(re.search(r"^sequential\s+\d+\s+([\d.]+)", (d / "gates.rpt").read_text(), re.M).group(1))
    t = (d / "timing.rpt").read_text()
    slack_ps = float(re.search(r"Slack:=\s+(-?\d+)", t).group(1))
    period_ns = float(re.search(r"create_clock .*-period ([\d.]+)", (d / "constraints.sdc").read_text()).group(1))
    return {"area": area, "seq": seq, "period": period_ns, "slack_ns": slack_ps / 1000}


def power(design, run, instance):
    """(dynamic mW, leakage mW, duration ns) of one instance in one Joules run."""
    rpt = PWR / f"{design}_{run}" / "power_hier.rpt"
    if not rpt.exists():
        return None
    for line in rpt.read_text().splitlines():
        f = line.split()
        if len(f) >= 8 and f[-1] == instance:
            leak, internal, switching = float(f[2]), float(f[3]), float(f[4])
            dur = float(re.search(r"\(DURATION ([\d.]+)\)", (PWR / f"{run}.saif").read_text()).group(1))
            return internal + switching, leak, dur
    return None


def energy_per_block(design, run_prefix, instance, cyc_per_block):
    """Dynamic energy from the run difference + leakage at F_NOMINAL_HZ, in pJ."""
    big, small = power(design, f"{run_prefix}_4096", instance), power(design, f"{run_prefix}_16", instance)
    if not big or not small:
        return None
    dyn_pj = (big[0] * big[2] - small[0] * small[2]) / BLOCKS_DIFF   # mW * ns = pJ
    leak_pj = big[1] * cyc_per_block / F_NOMINAL_HZ * 1e9            # mW * ns
    return dyn_pj, leak_pj


def main():
    cyc = cycles()
    per_block = {i: cyc[i][max(cyc[i])] / (max(cyc[i]) / 16) for i in cyc}

    zkne, zkn = synth("zkne"), synth("zkn")
    otm, otu = synth("ot_masked"), synth("ot_unmasked")
    zkne_fast = synth("zkne_1.0ns")

    e_zkn = energy_per_block("zkn", "zkne", "/zkn_full/i_zkn/i_aes", per_block["zkne"])
    e_ot = energy_per_block("ot_masked", "ot", "/ot_aes", per_block["ot"])

    L = ["# AES-128 on CVA6: software vs Zkne vs OpenTitan accelerator", "",
         "All numbers from RTL simulation (VCS) of upstream CVA6 and synthesis",
         "(Genus/Joules) at TSMC 65 nm LP, typical corner (1.2 V, 25 C).", "",
         "## Speed (cycles on CVA6)", "",
         "| Method | Key setup | 1 block (16 B) | 1 KB | 4 KB | Cycles/block (4 KB) | Speed-up vs software |",
         "|---|---:|---:|---:|---:|---:|---:|"]
    for i in ("sw", "zkne", "ot"):
        c = cyc[i]
        L.append(f"| {NAMES[i]} | {c[0]:,} | {c[16]:,} | {c[1024]:,} | {c[4096]:,} | "
                 f"{per_block[i]:.1f} | {per_block['sw'] / per_block[i]:.1f}x |")

    L += ["", "## Area and timing (65 nm)", "",
          "| Block | Clock target | Area (um^2) | kGE | Logic only, no registers (kGE) | Worst slack (ns) |",
          "|---|---:|---:|---:|---:|---:|"]
    rows = [("Zkne unit (4 encryption instructions)", zkne), ("Full Zkn unit in CVA6 (enc+dec+SHA-2)", zkn),
            ("OpenTitan AES, masked (Carfield default)", otm), ("OpenTitan AES, unmasked", otu)]
    for name, s in rows + [("Zkne unit, tighter clock", zkne_fast)]:
        if s:
            L.append(f"| {name} | {s['period']:g} ns ({1000 / s['period']:.0f} MHz) | {s['area']:,.0f} | "
                     f"{s['area'] / KGE_UM2:.1f} | {(s['area'] - s['seq']) / KGE_UM2:.1f} | {s['slack_ns']:.3f} |")
    L += ["", "Zkne/Zkn rows include 201-204 wrapper registers that stand in for CVA6's",
          "existing pipeline registers; the 'logic only' column leaves them out.",
          "Slack >= 0 means the block meets that clock; negative slack is how much too slow.", ""]

    L += ["## Energy per 16-byte block (AES hardware only)", "",
          "| Block | Dynamic (pJ) | Leakage at 500 MHz (pJ) | Total (pJ) |", "|---|---:|---:|---:|"]
    for name, e in (("Zkn unit in CVA6, during Zkne AES", e_zkn), ("OpenTitan AES, masked", e_ot)):
        if e:
            L.append(f"| {name} | {e[0]:.1f} | {e[1]:.2f} | {e[0] + e[1]:.1f} |")
    L += ["", "Dynamic energy = (energy of the 4 KB run - energy of the 16 B run) / 255, so",
          "boot, key setup and the accelerator's reset-time reseeding cancel out.",
          "Not included: the CPU's own energy (CVA6 is busy ~107 cycles/block with Zkne,",
          "and mostly waiting on the bus with the accelerator).", ""]
    (RES / "summary.md").write_text("\n".join(L) + "\n")

    # Chart 1: cycles per block for each buffer size.
    sizes = [16, 1024, 4096]
    fig, ax = plt.subplots(figsize=(6.4, 3.6))
    w = 0.26
    for k, i in enumerate(("sw", "zkne", "ot")):
        ax.bar([x + (k - 1) * w for x in range(len(sizes))], [cyc[i][s] / (s / 16) for s in sizes], w, label=NAMES[i])
    ax.set_xticks(range(len(sizes)), [f"{s} B" for s in sizes])
    ax.set_yscale("log")
    ax.set_ylabel("cycles per 16-byte block (log)")
    ax.set_title("AES-128 encryption on CVA6")
    ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(RES / "cycles_per_block.png", dpi=150)

    # Chart 2: area.
    fig, ax = plt.subplots(figsize=(6.4, 3.0))
    names = [n for n, s in rows if s]
    vals = [s["area"] / KGE_UM2 for _, s in rows if s]
    ax.barh(names, vals)
    for y, v in enumerate(vals):
        ax.text(v, y, f" {v:.0f}", va="center", fontsize=8)
    ax.set_xlabel("area (kGE, 65 nm)")
    ax.invert_yaxis()
    fig.tight_layout()
    fig.savefig(RES / "area.png", dpi=150)
    print((RES / "summary.md").read_text())


if __name__ == "__main__":
    main()
