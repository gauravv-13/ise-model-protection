# ISE-Based Model Protection for RISC-V AI Accelerators

Protecting neural-network models on a RISC-V SoC using the host CPU's own AES
instructions (RISC-V Zkne on CVA6) instead of the on-chip security engine. The
CVA6 host decrypts (AES-CTR) and checks (AES-CMAC) every model block (weights,
layer descriptors and kernel code) before the PULP accelerator clusters use it.
We compare area, load latency and CPU cost against Carfield's OpenTitan-based
security island, and test against bit-flip (RowHammer-style) and power
side-channel attacks.

Platform: PULP's Carfield SoC. Honours research project, IIIT Hyderabad.

## Folder guide

| Path | Contents |
|------|----------|
| `docs/proposal` | Research proposal |
| `docs/references` | Paper notes |
| `env/` | Environment setup (`setup.sh`: tool paths, Python env) |
| `hw/patches` | Changes to CVA6 / Carfield |
| `hw/rtl` | Own RTL (e.g. masked AES round) |
| `third_party/` | Carfield and upstream CVA6, fetched by `scripts/setup_*.sh` (git-ignored) |
| `deps/` | Pinned upstream commits |
| `scripts/` | Setup, simulation (VCS), synthesis (Genus) and power (Joules) drivers |
| `hw/rtl/aes_periph` | OpenTitan AES as a CVA6 peripheral |
| `hw/synth` | Synthesis and power scripts and wrappers |
| `sw/tests/aes_compare` | AES-128: software vs Zkne vs OpenTitan accelerator |
| `sw/loader` | AES-CTR + CMAC model loader (RISC-V assembly, Zkne) |
| `sw/drivers` | Security-island mailbox driver |
| `sw/kernels` | Cluster NN kernels |
| `sw/tests/vectors` | AES / CMAC / Zkne test vectors |
| `models/train` | PyTorch training and quantization |
| `models/export` | Export to binary model image |
| `tools/encrypt` | Model encryption and packing |
| `tools/bitflip` | Bit-flip fault injector |
| `tools/leakage` | TVLA / CPA leakage analysis |
| `sim/spike` | Spike ISA simulation |
| `sim/rtl` | RTL simulation |
| `fpga/` | FPGA prototype (stretch goal) |
| `experiments/e1_cost` | Area, load latency, CPU cost vs. security island |
| `experiments/e2_bitflip` | Bit-flip robustness |
| `experiments/e3_leakage` | Power side-channel leakage |
| `experiments/e4_granularity` | Protection block-size study |
| `paper/` | Paper / thesis write-up |

Each experiment folder has `config/`, `scripts/` and `results/`.

## Getting started

