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

Current focus (small project for the advisor, 2026-11): AES-128 on CVA6 three
ways (software, Zkne instructions, OpenTitan AES accelerator on CVA6's bus),
compared in cycles, area and energy. Carfield's own CVA6 has no Zkn, so
upstream CVA6 runs standalone in VCS. See `experiments/e1_cost/`.

See `README.md` for the folder guide.

## Conventions

- Heavy work (building Carfield, toolchains, RTL simulation, synthesis) runs on
  the shared Linux workstation, not on the laptop.
- Large files (datasets, traces, waveforms, bulk results, tool installs) stay
  outside the repo. Keep only small summarized results in `experiments/*/results`.
- Use at most `-j4` for builds and run long jobs with `nice` (shared machine).
- Ask before any large download (toolchains, datasets, submodules, EDA tools).
- Upstream code lives in git-ignored `third_party/` (Carfield, CVA6), fetched at
  the commits in `deps/` by `scripts/setup_carfield.sh` and `scripts/setup_cva6.sh`.
  Never edit it by hand: changes go in `hw/patches/` and the setup scripts apply them.
- Source `env/setup.sh` before running tools.
- Main flows: `scripts/cva6_sim.sh` (VCS), `scripts/synth.sh` (Genus),
  `scripts/power.sh` (Joules). Outputs in `build/`, long logs in `logs/` (both ignored).
- Never copy PDK/library files into the repo, and never commit licence server
  addresses or details about other users.
- Commit on branch `setup`; ask before pushing to `main`.
