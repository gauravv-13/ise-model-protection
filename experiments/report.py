#!/usr/bin/env python3
"""Collect the measurements into experiments/results/.

Reads the RTL simulation logs (logs/run_<model>_t<tile>_<method>.log), the
Genus reports (build/synth/*/) and build/models/models.json, and writes

    load_cycles.csv   one row per model load (every repetition)
    synth.csv         area, slack and instance areas per synthesis run
    summary.md        the tables of the report
    numbers.json      the headline numbers, formatted
    *.png             charts

    .venv/bin/python experiments/report.py
"""
import csv
import glob
import json
import os
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "experiments", "results")
NAND2_UM2 = 1.44            # ND2D1 in tcbn65lp: area of one gate equivalent
F_CLK_MHZ = 250.0           # clock used to turn cycles into time (all designs meet 4 ns)

METHODS = ["none", "sw", "zkne", "eng_unmasked", "eng_masked"]
LABEL = {"none": "No protection (copy only)", "sw": "Software AES (baseline)",
         "zkne": "A: Zkne instructions", "eng_unmasked": "B: OpenTitan AES + DMA, unmasked",
         "eng_masked": "B: OpenTitan AES + DMA, masked"}
SHORT = {"none": "No protection", "sw": "Software AES", "zkne": "A: Zkne", "eng_unmasked": "B: engine",
         "eng_masked": "B: engine, masked"}
# Categorical colors in fixed order (blue, orange, aqua, yellow); grey for the
# no-protection reference. Text stays in ink colors.
COLOR = {"zkne": "#2a78d6", "eng_unmasked": "#eb6834", "eng_masked": "#1baf7a", "sw": "#eda100",
         "none": "#898781"}
INK, INK2, MUTED, GRID, AXIS, SURFACE = "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7", "#fcfcfb"
MODEL_NAME = {"cnn": "Tiny CNN", "mlp_s": "MLP 784-128-10", "mlp_l": "MLP 784-1024-256-10"}


# ----------------------------------------------------------------------------
# Inputs
# ----------------------------------------------------------------------------
def read_loads():
    rows = []
    for path in sorted(glob.glob(os.path.join(ROOT, "logs", "run_*_t*_*.log"))):
        m = re.match(r"run_(\w+?)_t(\d+)_(\w+)\.log", os.path.basename(path))
        text = open(path, errors="replace").read()
        if "ALL PASS" not in text:
            print(f"!! {os.path.basename(path)}: no ALL PASS, skipped")
            continue
        nn = re.search(r"CHECK nn images=(\d+) correct=(\d+) cycles=(\d+) outputs_match PASS", text)
        for line in text.splitlines():
            if not line.startswith("RESULT") or "what=load" not in line:
                continue
            f = dict(kv.split("=") for kv in line.split()[1:])
            rows.append({"model": m.group(1), "bytes": int(f["bytes"]), "tile": int(f["tile"]),
                         "tiles": int(f["tiles"]), "method": f["method"], "rep": int(f["rep"]),
                         "total": int(f["total"]), "copy_in": int(f["copy_in"]), "crypto": int(f["crypto"]),
                         "wait": int(f["wait"]), "copy_out": int(f["copy_out"]), "instret": int(f["instret"]),
                         "nn_images": int(nn.group(1)) if nn else 0,
                         "tamper_rejected": int("CHECK tamper REJECTED PASS" in text)})
    return rows


def read_synth():
    rows = []
    for d in sorted(glob.glob(os.path.join(ROOT, "build", "synth", "*"))):
        area_rpt, timing_rpt = os.path.join(d, "area.rpt"), os.path.join(d, "timing.rpt")
        if not (os.path.exists(area_rpt) and os.path.exists(timing_rpt)):
            continue
        name = os.path.basename(d)
        m = re.match(r"(.+?)(?:_([\d.]+)ns)?$", name)
        design, period = m.group(1), float(m.group(2) or 4.0)
        top, after_rule = None, False
        for line in open(area_rpt):                 # first row under the header rule: the top module
            if line.startswith("-----"):
                after_rule = True
            elif after_rule:
                top = float(re.findall(r"\d+\.\d+", line)[-1])     # Total-Area
                break
        slack = None
        for line in open(timing_rpt):
            s = re.search(r"Slack:=\s*(-?\d+)", line) or re.search(r"slack.*?(-?\d+)\s*ps", line, re.I)
            if s:
                slack = int(s.group(1)) / 1000.0
                break
        rows.append({"design": design, "period_ns": period, "area_um2": top, "kge": top / NAND2_UM2 / 1000,
                     "slack_ns": slack})
    return rows


# ----------------------------------------------------------------------------
# Tables
# ----------------------------------------------------------------------------
def steady(rows, model, method, tile=4096):
    """The last repetition (warm caches) of one configuration."""
    sel = [r for r in rows if (r["model"], r["method"], r["tile"]) == (model, method, tile)]
    return max(sel, key=lambda r: r["rep"]) if sel else None


def fmt(n):
    return f"{n:,.0f}"

# ----------------------------------------------------------------------------
# Cost model and break-even
# ----------------------------------------------------------------------------
def fit(points):
    """Least squares for cycles = a * blocks + b * tiles. points: (blocks, tiles, cycles)."""
    sxx = sum(x * x for x, _, _ in points); sxy = sum(x * y for x, y, _ in points)
    syy = sum(y * y for _, y, _ in points)
    sxz = sum(x * z for x, _, z in points); syz = sum(y * z for _, y, z in points)
    det = sxx * syy - sxy * sxy
    if abs(det) < 1e-9:                      # one tile size only: no per-tile term
        return sxz / sxx, 0.0
    return (sxz * syy - syz * sxy) / det, (syz * sxx - sxz * sxy) / det


def synth_kge(synth, design, period=4.0):
    for r in synth:
        if r["design"] == design and abs(r["period_ns"] - period) < 1e-6:
            return r["kge"]
    return None


def analyse(loads, synth, md):
    last = {}
    for r in loads:                           # last repetition of every configuration
        key = (r["model"], r["method"], r["tile"])
        if key not in last or r["rep"] > last[key]["rep"]:
            last[key] = r
    res = {"fit": {}, "area": {}}
    for method in METHODS[1:]:
        pts = [(r["bytes"] / 16, r["tiles"], r["crypto"]) for r in last.values() if r["method"] == method]
        if pts:
            res["fit"][method] = fit(pts)
    none = [r for r in last.values() if r["method"] == "none"]
    copy_cpb = sum(r["copy_in"] for r in none) / sum(r["bytes"] for r in none) if none else None
    res["copy_cpb"] = copy_cpb

    md += ["", "## Cost model, fitted to the measurements", "",
           "Check + decrypt cycles = a x (16-byte blocks) + b x (tiles), least squares over all runs.", "",
           "| Method | a: cycles per block | cycles per byte | b: cycles per tile |", "|---|---:|---:|---:|"]
    for method, (a, b) in res["fit"].items():
        md.append(f"| {LABEL[method]} | {a:.1f} | {a / 16:.2f} | {fmt(b)} |")

    zk = [r for r in last.values() if r["method"] == "zkne" and r["tile"] == 4096]
    if zk and none:
        r = max(zk, key=lambda r: r["bytes"])
        n = next(x for x in none if x["model"] == r["model"])
        instr = r["instret"] - n["instret"]                  # instructions of check + decrypt
        blocks = r["bytes"] / 16
        cpi = r["crypto"] / instr
        res["zkne"] = {"instr_per_block": instr / blocks, "cpi": cpi,
                       "c_ovh": r["crypto"] / blocks - 40 * cpi}
        md += ["", f"Option A (proposal model T_A = N_blk x (2 R k CPI + c_ovh), 2 R k = 40): "
               f"{instr / blocks:.1f} instructions per block at CPI {cpi:.2f}; the 40 AES instructions "
               f"take {40 * cpi:.0f} cycles, so c_ovh = {r['crypto'] / blocks - 40 * cpi:.0f} cycles per block "
               "(44 round-key loads, 44 XORs, data load/store, counter)."]
    for method in ("eng_unmasked", "eng_masked"):
        e = [r for r in last.values() if r["method"] == method and r["tile"] == 4096]
        if e:
            r = max(e, key=lambda r: r["bytes"])
            per_block = r["wait"] / (2 * r["bytes"] / 16)       # two passes over the data
            setup = (r["crypto"] - r["wait"]) / r["tiles"]
            res[method] = {"engine_cycles_per_block": per_block, "cpu_per_tile": setup}
            md += ["", f"{LABEL[method]} (T_B = max(S/BW_mem, N_blk/Theta_eng) + c_setup): the engine takes "
                   f"{per_block:.1f} cycles per block per pass (Theta_eng = 1/{per_block:.1f}), two passes "
                   f"(CMAC, then CTR); c_setup = {fmt(setup)} CPU cycles per tile."
                   + (f" Memory is not the limit: a DMA copy takes {copy_cpb:.2f} cycles per byte "
                      f"(BW_mem = {1 / copy_cpb:.1f} bytes per cycle)." if copy_cpb else "")]

    # Area added by each option (kGE).
    base = synth_kge(synth, "cva6_base")
    for name, design in (("zkne", "cva6_zkne"), ("zkn", "cva6_zkn")):
        k = synth_kge(synth, design)
        if base and k:
            res["area"][name] = k - base
    for name, design in (("eng_unmasked", "engine_unmasked"), ("eng_masked", "engine_masked"), ("dma", "dma"),
                         ("cva6_base", "cva6_base")):
        k = synth_kge(synth, design)
        if k:
            res["area"][name] = k

    if "zkne" in res["fit"] and "eng_unmasked" in res["fit"]:
        md += ["", "## Break-even", ""]
        a_a, b_a = res["fit"]["zkne"]
        for method in ("eng_unmasked", "eng_masked"):
            if method not in res["fit"]:
                continue
            a_b, b_b = res["fit"][method]
            n = (b_b - b_a) / (a_a - a_b)
            md.append(f"- Time: {SHORT[method]} is faster than Zkne once a tile has more than {n:.0f} blocks "
                      f"({fmt(16 * n)} bytes); for large tiles it is {a_a / a_b:.2f}x faster.")
        ar = res["area"]
        if "zkne" in ar and "eng_unmasked" in ar:
            md.append(f"- Area: Zkne adds {ar['zkne']:.1f} kGE to CVA6 ({100 * ar['zkne'] / ar['cva6_base']:.2f} % "
                      f"of the {ar['cva6_base']:.0f} kGE core logic); the unmasked engine with DMA is "
                      f"{ar['eng_unmasked']:.1f} kGE, {ar['eng_unmasked'] / ar['zkne']:.1f}x as much.")
            for method, key in (("zkne", "zkne"), ("eng_unmasked", "eng_unmasked"), ("eng_masked", "eng_masked")):
                if key in ar and method in res["fit"]:
                    cpb = res["fit"][method][0] / 16
                    md.append(f"  - {SHORT[method]}: {1000 / cpb / ar[key]:.1f} bytes per 1000 cycles per added kGE")
        cpb_a = a_a / 16
        md.append(f"- CPU: with Zkne the CPU does all the work, {cpb_a:.2f} cycles per byte. At {F_CLK_MHZ:.0f} MHz "
                  f"that is {F_CLK_MHZ * 1e6 / cpb_a / 1e6:.1f} MB/s with the whole CPU, "
                  f"{0.1 * F_CLK_MHZ * 1e6 / cpb_a / 1e6:.2f} MB/s with 10 % of it. "
                  "Beyond that load rate (model size x reloads per second) the engine is the only option.")
    return res


def charts(loads, synth, res):
    plt.rcParams.update({"font.size": 9, "font.family": "DejaVu Sans", "text.color": INK,
                         "axes.labelcolor": INK2, "axes.edgecolor": AXIS, "xtick.color": MUTED,
                         "ytick.color": MUTED, "axes.spines.top": False, "axes.spines.right": False,
                         "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE})

    def style(ax, grid_axis="both"):
        ax.grid(True, which="major", axis=grid_axis, color=GRID, linewidth=0.6)
        ax.set_axisbelow(True)
        ax.tick_params(length=0, labelcolor=INK2)

    # 1. Load time against model size.
    fig, ax = plt.subplots(figsize=(6.6, 3.9))
    for method in METHODS:
        pts = sorted((r["bytes"], r["total"]) for model in MODEL_NAME for r in [steady(loads, model, method)] if r)
        if not pts:
            continue
        ax.plot(*zip(*pts), marker="o", markersize=5, linewidth=2, color=COLOR[method], label=LABEL[method])
        dy = {"zkne": 5, "eng_masked": -5}.get(method, 0)        # these two end close together
        ax.annotate(SHORT[method], pts[-1], xytext=(7, dy), textcoords="offset points", va="center",
                    fontsize=8, color=INK2)
    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_xlim(right=ax.get_xlim()[1] * 4.5)
    ax.set_xlabel("Model size (bytes)"); ax.set_ylabel("Model-load time (CVA6 cycles)")
    style(ax)
    ax.legend(frameon=False, fontsize=7.5, loc="lower right")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "load_time.png"), dpi=200); plt.close(fig)

    # 2. Cycles per byte: whole check + decrypt, and the part the CPU itself works.
    model = next((m for m in ("mlp_l", "mlp_s", "cnn") if steady(loads, m, "zkne")), None)
    if model:
        fig, axes = plt.subplots(1, 2, figsize=(6.6, 2.5), sharey=True)
        methods = [m for m in METHODS[1:] if steady(loads, model, m)][::-1]
        for ax, title, value in ((axes[0], "Check + decrypt, cycles per byte", lambda r: r["crypto"]),
                                 (axes[1], "of which the CPU is busy", lambda r: r["crypto"] - r["wait"])):
            vals = [value(steady(loads, model, m)) / steady(loads, model, m)["bytes"] for m in methods]
            ax.barh(range(len(methods)), vals, height=0.55, color=[COLOR[m] for m in methods])
            for i, v in enumerate(vals):
                ax.text(v * 1.12, i, f"{v:.2f}" if v < 100 else f"{v:.0f}", va="center", fontsize=8, color=INK)
            ax.set_xscale("log"); ax.set_xlim(0.1, 600)
            ax.set_title(title, fontsize=9, loc="left", color=INK)
            ax.set_yticks(range(len(methods))); ax.set_yticklabels([SHORT[m] for m in methods])
            style(ax, "x")
        fig.tight_layout(); fig.savefig(os.path.join(OUT, "cycles_per_byte.png"), dpi=200); plt.close(fig)

    # 3. Added area.
    ar = res["area"]
    bars = [(k, lab, col) for k, lab, col in (
        ("zkne", "A: Zkne in CVA6", COLOR["zkne"]), ("zkn", "A: full Zkn in CVA6", COLOR["zkne"]),
        ("eng_unmasked", "B: engine, unmasked", COLOR["eng_unmasked"]),
        ("eng_masked", "B: engine, masked", COLOR["eng_masked"])) if k in ar]
    if bars:
        fig, ax = plt.subplots(figsize=(6.6, 2.4))
        for i, (k, lab, col) in enumerate(bars[::-1]):
            total, dma = ar[k], (ar.get("dma", 0) if k.startswith("eng") else 0)
            ax.barh(i, total - dma, height=0.55, color=col)
            if dma:                                         # DMA share, lighter, with a gap
                ax.barh(i, dma, left=total - dma, height=0.55, color=col, alpha=0.45,
                        edgecolor=SURFACE, linewidth=2)
                ax.text(total - dma / 2, i, "DMA", ha="center", va="center", fontsize=7, color=INK)
            ax.text(total + 1.5, i, f"{total:.1f} kGE", va="center", fontsize=8, color=INK)
        ax.set_yticks(range(len(bars))); ax.set_yticklabels([b[1] for b in bars[::-1]])
        ax.set_xlabel("Added logic area (kGE, 65 nm LP)")
        ax.set_xlim(0, max(ar[b[0]] for b in bars) * 1.18)
        style(ax, "x")
        fig.tight_layout(); fig.savefig(os.path.join(OUT, "area.png"), dpi=200); plt.close(fig)

    # 4. Break-even map: model size against reload rate.
    if "zkne" in res["fit"] and "eng_unmasked" in res["fit"]:
        fig, ax = plt.subplots(figsize=(6.6, 3.9))
        sizes = [10e3 * 10 ** (i / 20) for i in range(61)]                 # 10 KB .. 10 MB
        f_clk = F_CLK_MHZ * 1e6

        def rate(method, share):
            a, b = res["fit"][method]
            return [share * f_clk / (a * s / 16 + b * s / 4096) for s in sizes]
        a10, a100, b100 = rate("zkne", 0.1), rate("zkne", 1.0), rate("eng_unmasked", 1.0)
        lo, hi = 0.1, 2e5
        ax.fill_between(sizes, lo, a10, color=COLOR["zkne"], alpha=0.16, linewidth=0)
        ax.fill_between(sizes, a10, a100, color=COLOR["zkne"], alpha=0.07, linewidth=0)
        ax.fill_between(sizes, a100, b100, color=COLOR["eng_unmasked"], alpha=0.14, linewidth=0)
        ax.plot(sizes, a10, color=COLOR["zkne"], linewidth=2, linestyle=(0, (4, 2)), label="A: Zkne uses 10 % of the CPU")
        ax.plot(sizes, a100, color=COLOR["zkne"], linewidth=2, label="A: Zkne uses the whole CPU")
        ax.plot(sizes, b100, color=COLOR["eng_unmasked"], linewidth=2, label="B: engine is always busy")
        ax.set_xscale("log"); ax.set_yscale("log"); ax.set_xlim(sizes[0], sizes[-1]); ax.set_ylim(lo, hi)
        def at(curve, x):                                   # value of a curve at size x
            return curve[min(range(len(sizes)), key=lambda i: abs(sizes[i] - x))]
        for x, y, text in ((1.2e5, at(a10, 1.2e5) / 12, "A is enough: under 10 % of the CPU"),
                           (1.2e5, (at(a10, 1.2e5) * at(a100, 1.2e5)) ** 0.5, "A works, at 10-100 % of the CPU"),
                           (1.2e5, (at(a100, 1.2e5) * at(b100, 1.2e5)) ** 0.5, "only B keeps up"),
                           (1.2e5, at(b100, 1.2e5) * 8, "neither keeps up")):
            ax.text(x, y, text, fontsize=8, color=INK2, ha="center", va="center", rotation=-15)
        ax.set_xlabel("Model size (bytes)"); ax.set_ylabel(f"Model reloads per second (at {F_CLK_MHZ:.0f} MHz)")
        style(ax)
        ax.legend(frameon=False, fontsize=7.5, loc="upper right")
        fig.tight_layout(); fig.savefig(os.path.join(OUT, "break_even.png"), dpi=200); plt.close(fig)

def key_numbers(loads, synth, models, res):
    """The headline numbers as ready-to-print strings, for the written report."""
    n = {"f_clk_mhz": f"{F_CLK_MHZ:.0f}"}
    for name, m in models.items():
        n[f"{name}.weights"] = fmt(m["weight_bytes"]); n[f"{name}.blob"] = fmt(m["blob_bytes"])
        n[f"{name}.acc_float"] = f"{100 * m['acc_float']:.2f}"; n[f"{name}.acc_int8"] = f"{100 * m['acc_int8']:.2f}"
    for model in MODEL_NAME:
        sw, zk = steady(loads, model, "sw"), steady(loads, model, "zkne")
        for method in METHODS:
            r = steady(loads, model, method)
            if not r:
                continue
            k = f"{model}.{method}."
            n[k + "total"] = fmt(r["total"]); n[k + "crypto"] = fmt(r["crypto"])
            n[k + "cpb"] = f"{r['crypto'] / r['bytes']:.2f}" if r["crypto"] / r["bytes"] < 100 else f"{r['crypto'] / r['bytes']:.0f}"
            n[k + "busy"] = fmt(r["crypto"] - r["wait"])
            n[k + "busy_cpb"] = f"{(r['crypto'] - r['wait']) / r['bytes']:.2f}"
            n[k + "tile_latency"] = fmt(r["total"] / r["tiles"])
            n[k + "ms"] = f"{r['total'] / F_CLK_MHZ / 1e3:.1f}"            # at F_CLK
            if sw and r["crypto"]:
                n[k + "vs_sw"] = f"{sw['crypto'] / r['crypto']:.1f}"
            if zk and r["crypto"]:
                n[k + "vs_zkne"] = f"{zk['crypto'] / r['crypto']:.2f}"
        none = steady(loads, model, "none")
        if none:
            n[f"{model}.copy_cpb"] = f"{none['total'] / none['bytes']:.2f}"
    for r in loads:
        if r["model"] == "mlp_s" and r["rep"] == max(x["rep"] for x in loads if (x["model"], x["method"], x["tile"]) == ("mlp_s", r["method"], r["tile"])):
            n[f"tile.{r['tile']}.{r['method']}"] = f"{r['crypto'] / r['bytes']:.2f}"
    for method, (a, b) in res["fit"].items():
        n[f"fit.{method}.block"] = f"{a:.1f}"; n[f"fit.{method}.cpb"] = f"{a / 16:.2f}"; n[f"fit.{method}.tile"] = fmt(b)
    if "zkne" in res:
        n["zkne.instr_per_block"] = f"{res['zkne']['instr_per_block']:.0f}"; n["zkne.cpi"] = f"{res['zkne']['cpi']:.2f}"
        n["zkne.c_ovh"] = f"{res['zkne']['c_ovh']:.0f}"; n["zkne.aes_cycles"] = f"{40 * res['zkne']['cpi']:.0f}"
    for method in ("eng_unmasked", "eng_masked"):
        if method in res:
            n[f"{method}.block_cycles"] = f"{res[method]['engine_cycles_per_block']:.1f}"
            n[f"{method}.cpu_per_tile"] = fmt(res[method]["cpu_per_tile"])
    if res.get("copy_cpb"):
        n["copy.cpb"] = f"{res['copy_cpb']:.2f}"; n["copy.bytes_per_cycle"] = f"{1 / res['copy_cpb']:.1f}"
    ar = res["area"]
    for k, v in ar.items():
        n[f"area.{k}"] = f"{v:.1f}"
    if "cva6_base" in ar:
        for k in ("zkne", "zkn"):
            if k in ar:
                n[f"area.{k}_pct"] = f"{100 * ar[k] / ar['cva6_base']:.1f}"
    for k in ("eng_unmasked", "eng_masked"):
        if k in ar and "dma" in ar:
            n[f"area.{k}_aes"] = f"{ar[k] - ar['dma']:.1f}"
        if k in ar and "zkne" in ar:
            n[f"area.{k}_vs_zkne"] = f"{ar[k] / ar['zkne']:.1f}"
        if k in ar and k in res["fit"]:
            n[f"eff.{k}"] = f"{1000 / (res['fit'][k][0] / 16) / ar[k]:.1f}"
    if "zkne" in ar and "zkne" in res["fit"]:
        n["eff.zkne"] = f"{1000 / (res['fit']['zkne'][0] / 16) / ar['zkne']:.1f}"
    u = synth_kge(synth, "zkne_unit")
    if u:
        n["area.zkne_unit"] = f"{u:.1f}"
    for r in synth:                                      # tight-clock runs: best period reached
        if r["design"].startswith("cva6") and r["period_ns"] < 4.0:
            reached = r["period_ns"] - min(r["slack_ns"], 0.0)
            n[f"fmax.{r['design']}"] = f"{1000 / reached:.0f}"; n[f"fmax.{r['design']}_ns"] = f"{reached:.2f}"
            n[f"fmax.{r['design']}_target"] = f"{r['period_ns']:g}"; n[f"fmax.{r['design']}_kge"] = f"{r['kge']:.1f}"
    if "zkne" in res["fit"]:
        a_a, b_a = res["fit"]["zkne"]
        n["rate.zkne_full"] = f"{F_CLK_MHZ / (a_a / 16):.1f}"; n["rate.zkne_10pct"] = f"{0.1 * F_CLK_MHZ / (a_a / 16):.1f}"
        for method in ("eng_unmasked", "eng_masked"):
            if method in res["fit"]:
                a_b, b_b = res["fit"][method]
                blocks = (b_b - b_a) / (a_a - a_b)
                n[f"even.{method}.bytes"] = fmt(16 * blocks); n[f"even.{method}.ratio"] = f"{a_a / a_b:.1f}"
                n[f"rate.{method}"] = f"{F_CLK_MHZ / ((a_b + b_b / 256) / 16):.0f}"       # MB/s, 4 KB tiles
    return n


def main():
    os.makedirs(OUT, exist_ok=True)
    loads, synth = read_loads(), read_synth()
    models = json.load(open(os.path.join(ROOT, "build", "models", "models.json")))

    with open(os.path.join(OUT, "load_cycles.csv"), "w", newline="") as fh:
        cols = ["model", "bytes", "tile", "tiles", "method", "rep", "total", "copy_in", "crypto", "wait",
                "copy_out", "instret", "nn_images", "tamper_rejected"]
        w = csv.DictWriter(fh, cols)
        w.writeheader()
        w.writerows(loads)
    with open(os.path.join(OUT, "synth.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["design", "period_ns", "area_um2", "kge", "slack_ns"])
        for r in synth:
            w.writerow([r["design"], r["period_ns"], f"{r['area_um2']:.0f}", f"{r['kge']:.1f}", r["slack_ns"]])

    md = ["# Results", "",
          "RTL simulation (VCS) of upstream CVA6 with the AES engines on its AXI bus; synthesis with",
          "Genus at TSMC 65 nm LP, typical corner (1.2 V, 25 C). Cycle counts are from the second of two",
          "loads (warm caches) unless noted. Regenerate with `experiments/report.py`.", ""]

    md += ["## Workloads", "", "| Model | Weights (bytes) | Model blob (bytes) | Accuracy, float | Accuracy, int8 |",
           "|---|---:|---:|---:|---:|"]
    for name, m in models.items():
        md.append(f"| {MODEL_NAME[name]} | {fmt(m['weight_bytes'])} | {fmt(m['blob_bytes'])} | "
                  f"{100 * m['acc_float']:.2f} % | {100 * m['acc_int8']:.2f} % |")

    md += ["", "## Model-load time (4 KB tiles)", "",
           "Total = copy into L2 + check and decrypt + copy to L1. CPU busy = cycles the CPU itself works",
           "on crypto (for the engine: set-up and tag check, not the wait).", "",
           "| Model | Method | Total cycles | Check + decrypt | cycles/byte | CPU busy | vs software | vs Zkne |",
           "|---|---|---:|---:|---:|---:|---:|---:|"]
    for model in MODEL_NAME:
        sw, zk = steady(loads, model, "sw"), steady(loads, model, "zkne")
        for method in METHODS:
            r = steady(loads, model, method)
            if not r:
                continue
            cpb = r["crypto"] / r["bytes"]
            busy = r["crypto"] - r["wait"]
            vs_sw = f"{sw['crypto'] / r['crypto']:.1f}x" if sw and r["crypto"] else "-"
            vs_zk = f"{zk['crypto'] / r['crypto']:.2f}x" if zk and r["crypto"] else "-"
            md.append(f"| {MODEL_NAME[model]} | {LABEL[method]} | {fmt(r['total'])} | {fmt(r['crypto'])} | "
                      f"{cpb:.2f} | {fmt(busy)} | {vs_sw} | {vs_zk} |")

    tiles = sorted({r["tile"] for r in loads if r["model"] == "mlp_s"})
    if len(tiles) > 1:
        md += ["", "## Tile size (100 KB model): check + decrypt, cycles/byte", "",
               "| Tile | " + " | ".join(SHORT[m] for m in METHODS[2:]) + " |", "|---:|" + "---:|" * 3]
        for t in tiles:
            cells = []
            for method in METHODS[2:]:
                r = steady(loads, "mlp_s", method, t)
                cells.append(f"{r['crypto'] / r['bytes']:.2f}" if r else "-")
            md.append(f"| {fmt(t)} B | " + " | ".join(cells) + " |")

    if synth:
        md += ["", "## Area and timing (65 nm LP, logic only)", "",
               "| Design | Clock (ns) | Area (um^2) | kGE | Slack (ns) |", "|---|---:|---:|---:|---:|"]
        for r in synth:
            md.append(f"| {r['design']} | {r['period_ns']:g} | {fmt(r['area_um2'])} | {r['kge']:.1f} | "
                      f"{r['slack_ns']:+.3f} |")

    analysis = analyse(loads, synth, md)
    numbers = key_numbers(loads, synth, models, analysis)
    with open(os.path.join(OUT, "numbers.json"), "w") as fh:
        json.dump(numbers, fh, indent=1, sort_keys=True)
    with open(os.path.join(OUT, "summary.md"), "w") as fh:
        fh.write("\n".join(md) + "\n")
    print("\n".join(md))
    charts(loads, synth, analysis)


if __name__ == "__main__":
    main()
