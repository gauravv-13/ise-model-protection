#!/usr/bin/env python3
"""Collect the AES comparison numbers into one table and two charts.

Inputs (made by scripts/cva6_sim.sh and scripts/synth.sh):
  experiments/e1_cost/results/cva6_vcs_sw_zkne_ot.txt   cycle counts on CVA6
  build/synth/<design>/{qor,gates,timing,constraints}   Genus, 65 nm
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
KGE_UM2 = 1440.0          # 1000 x ND2D1 (1.44 um^2) in tcbn65lp

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




def main():
    cyc = cycles()
    per_block = {i: cyc[i][max(cyc[i])] / (max(cyc[i]) / 16) for i in cyc}

    zkne, zkn = synth("zkne"), synth("zkn")
    otm, otu = synth("ot_masked"), synth("ot_unmasked")
    zkne_fast = synth("zkne_1.0ns")


    L = ["# AES-128 on CVA6: software vs Zkne vs OpenTitan accelerator", "",
         "All numbers from RTL simulation (VCS) of upstream CVA6 and synthesis",
         "(Genus) at TSMC 65 nm LP, typical corner (1.2 V, 25 C).", "",
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
    ax.set_title("AES-128 encryption on CVA6", pad=24)
    ax.legend(frameon=False, fontsize=8, ncol=3, loc="lower center", bbox_to_anchor=(0.5, 1.0))
    fig.tight_layout()
    fig.savefig(RES / "cycles_per_block.png", dpi=150)

    # Chart 2: area.
    fig, ax = plt.subplots(figsize=(6.4, 2.4))
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
