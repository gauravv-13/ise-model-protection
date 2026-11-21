# ISE-Based Model Protection for RISC-V AI Accelerators

Two ways to decrypt (AES-CTR) and authenticate (AES-CMAC) neural-network
weights before an accelerator uses them, compared in area and model-load time:

- **Option A**: AES instructions (RISC-V Zkne) in the CVA6 host CPU.
- **Option B**: a dedicated AES engine, the OpenTitan AES block with a DMA on
  the system bus.

Baselines: no protection, and software AES on CVA6. Proposal:
`docs/proposal/`. Results: `experiments/results/summary.md`.

Honours research project, IIIT Hyderabad.

## Results (22 November 2026)

All 24 load measurements pass (decrypted model matches, flipped bit rejected,
int8 inference gives the expected outputs). With 4 KB tiles (details and
charts in `experiments/results/`):

| Method | Check + decrypt (cycles/byte) | CPU busy (cycles/byte) | Added logic area (65 nm) |
|---|---:|---:|---:|
| Software AES | 141 | 141 | none |
| A: Zkne in CVA6 | 9.6 | 9.6 | 5.9 kGE (Zkn unit alone; 1.6 % of CVA6 logic) |
| B: OpenTitan AES + DMA, unmasked | 2.7 | 0.40 | 51.7 kGE (DMA 13.8) |
| B: OpenTitan AES + DMA, masked | 7.5 | 0.44 | 106.1 kGE (DMA 13.8) |

- Option B is faster than A once a tile holds more than about 130 bytes
  (unmasked) or 470 bytes (masked), and keeps the CPU almost free.
- Option A gives about twice the throughput per added kGE of the unmasked
  engine (16.1 vs 8.6 bytes per 1000 cycles per kGE), and 12x the masked one.
- Fmax: CVA6 meets 2.5 ns (400 MHz) with and without Zkne; the critical path
  at 2.5 ns does not go through the AES unit. Higher clocks were not tried.
- Area of whole-CVA6 runs varies by 1 to 2 kGE between synthesis runs
  (CVA6 with full Zkn came out 1.3 kGE smaller than with Zkne only), so the
  added area of Zkne is taken from the Zkn unit synthesized alone (5.9 kGE,
  including about 200 wrapper registers); the CVA6 difference (6.6 kGE)
  agrees with it.

Not done: the written report.

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
