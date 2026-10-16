# CLAUDE.md

## Project

ISE-Based Model Protection for RISC-V AI Accelerators. Protecting neural-network
models on a RISC-V SoC using the host CPU's own AES instructions (RISC-V Zkne on
CVA6) instead of the on-chip security engine. The CVA6 host decrypts (AES-CTR)
and checks (AES-CMAC) every model block (weights, layer descriptors and kernel
code) before the PULP accelerator clusters use it. We compare area, load latency
and CPU cost against Carfield's OpenTitan-based security island, and test
against bit-flip (RowHammer-style) and power side-channel attacks.

Platform: PULP's Carfield SoC. Honours research project, IIIT Hyderabad.

See `README.md` for the folder guide.

## Conventions

- Heavy work (building Carfield, toolchains, RTL simulation, synthesis) runs on
  the shared Linux workstation, not on the laptop.
- Large files (datasets, traces, waveforms, bulk results, tool installs) stay
  outside the repo. Keep only small summarized results in `experiments/*/results`.
- Use at most `-j8` for builds (shared machine).
- Ask before any large download (toolchains, datasets, submodules, EDA tools).
- `hw/carfield` is reserved for the Carfield git submodule; do not create it by hand.
  Changes to upstream CVA6/Carfield go in `hw/patches`.
- Source `env/setup.sh` before running tools.
