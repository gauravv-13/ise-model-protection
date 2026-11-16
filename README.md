# ISE-Based Model Protection for RISC-V AI Accelerators

Two ways to decrypt (AES-CTR) and authenticate (AES-CMAC) neural-network
weights before an accelerator uses them, compared in area and model-load time:

- **Option A**: AES instructions (RISC-V Zkne) in the CVA6 host CPU.
- **Option B**: a dedicated AES engine, the OpenTitan AES block with a DMA on
  the system bus.

Baselines: no protection, and software AES on CVA6. Proposal:
`docs/proposal/`. Results and report: `experiments/results/`, `docs/report/`.

Honours research project, IIIT Hyderabad.

## What is measured, and on what

Upstream CVA6 (RV64GC with Zkn) runs in its own test harness (CVA6, AXI
crossbar, memory) in Synopsys VCS. The AES engines are added to that harness as
bus masters. Carfield's own CVA6 has no Zkn and Carfield only simulates in
QuestaSim, which the lab does not have, so the PULP cluster and HyperRAM are
not simulated: one DMA copy stands in for "off-chip memory to L2" and one for
"L2 to cluster L1". Area and timing come from Cadence Genus at TSMC 65 nm LP.

## Folder guide

| Path | Contents |
|------|----------|
| `docs/proposal` | Research proposal |
| `docs/report` | Final report (PDF and source) |
| `docs/workstation.md` | Lab workstation notes (tools, paths) |
| `env/setup.sh` | Environment setup (tool paths, Python env) |
| `deps/` | Pinned upstream commits (CVA6, OpenTitan) |
| `third_party/` | Upstream CVA6 and OpenTitan AES, fetched by `scripts/setup_*.sh` (git-ignored) |
| `hw/patches/cva6` | Our changes to CVA6, applied by `scripts/setup_cva6.sh` |
| `hw/engine` | Option B: DMA with AES streaming mode around OpenTitan AES, harness wrapper, unit test |
| `hw/synth` | Genus script and wrappers |
| `sw/loader` | Model loader: Zkne assembly (Option A), engine driver (Option B), software AES, int8 inference check |
| `models/train.py` | Trains and quantizes the int8 workloads (MNIST: tiny CNN, two MLPs) |
| `tools/` | Model image packer (AES-CTR + CMAC per tile) and AES reference |
| `scripts/` | Setup, simulation (VCS) and synthesis (Genus) drivers |
| `experiments/` | Sweep runner, report script, results |

## Reproduce

On the lab workstation (about 4 hours, mostly the software-AES run of the
1 MB model and CVA6 synthesis):

    source env/setup.sh
    scripts/setup_cva6.sh && scripts/setup_opentitan.sh
    python3 models/train.py                     # needs MNIST in ~/ise-data/mnist
    scripts/engine_tb.sh && scripts/engine_tb.sh masked
    make -C sw/loader MODEL=cnn METHOD=zkne spike
    scripts/cva6_sim.sh build
    experiments/run_sweep.sh
    for d in cva6_base cva6_zkne cva6_zkn engine_unmasked engine_masked; do scripts/synth.sh $d; done
    python3 experiments/report.py

MNIST (four `.gz` files, 11 MB) is not in the repository; `models/train.py`
reads it from `~/ise-data/mnist`.
