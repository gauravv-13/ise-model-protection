# CLAUDE.md

## Project

ISE-Based Model Protection for RISC-V AI Accelerators. Compare two ways to
decrypt (AES-CTR) and authenticate (AES-CMAC) neural-network weights before an
accelerator uses them: (A) Zkne AES instructions in the CVA6 host, (B) a
dedicated engine, OpenTitan AES + DMA on the system bus. Metrics: added area,
Fmax, model-load time, CPU busy time. Baselines: no protection, software AES.
Proposal: `docs/proposal/` (local only, git-ignored). Honours research project, IIIT Hyderabad.

Platform as built: upstream CVA6 (has Zkn) in its own VCS test harness, with
the engines added as AXI masters. Carfield's CVA6 has no Zkn and Carfield needs
QuestaSim, so the PULP cluster and HyperRAM are not simulated (DMA copies stand
in for them). Synthesis: Genus, TSMC 65 nm LP.

See `README.md` for the folder guide and the full reproduce sequence.

## Conventions

- Heavy work (RTL simulation, synthesis) runs on the shared Linux workstation,
  not on the laptop.
- Large files (datasets, traces, waveforms, bulk results, tool installs) stay
  outside the repo. Keep only small summarized results in `experiments/results`.
  MNIST lives in `~/ise-data/mnist`.
- Use at most `-j4` for builds and run long jobs with `nice` (shared machine).
  RAM is the tight resource: check `free -h` before starting Genus on CVA6.
- Ask before any large download (toolchains, datasets, submodules, EDA tools).
- Upstream code lives in git-ignored `third_party/` (CVA6, OpenTitan AES),
  fetched at the commits in `deps/` by `scripts/setup_cva6.sh` and
  `scripts/setup_opentitan.sh`. Changes to CVA6 go in `hw/patches/cva6/`
  (regenerate the patch with `git diff` in the checkout); the setup script
  applies them.
- Source `env/setup.sh` before running tools.
- Main flows: `scripts/cva6_sim.sh` (VCS harness), `scripts/engine_tb.sh`
  (engine unit test), `experiments/run_sweep.sh` (all load measurements),
  `scripts/synth.sh` (Genus), `experiments/report.py` (tables and charts).
  Outputs in `build/`, long logs in `logs/` (both ignored).
- The harness must be built with `NO_TRACE` (the scripts do): CVA6's
  instruction tracers otherwise write about 100 bytes per instruction.
- Never copy PDK/library files into the repo, and never commit licence server
  addresses or details about other users.
- Commit on branch `setup`; ask before pushing to `main`.
