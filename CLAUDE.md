# CLAUDE.md

Protecting neural-network models on a RISC-V SoC using the host CPU's own AES instructions (RISC-V Zkne on CVA6) instead of the on-chip security engine. The CVA6 host decrypts with AES-CTR and checks with AES-CMAC every model block—weights, layer descriptors, and kernel code—before PULP accelerator clusters use it. Compare area, load latency, and CPU cost against Carfield's OpenTitan-based security island, and test against bit-flip (RowHammer-style) and power side-channel attacks. Platform: PULP's Carfield SoC. Honours research project, IIIT Hyderabad.

## Conventions
- Heavy work (Carfield, toolchains, RTL simulation, synthesis) runs on a shared Linux workstation.
- Keep large files outside this repository.
- Use at most `-j8` for builds.
- Ask before large downloads.
- This repository skeleton intentionally contains no code, dependencies, or CI/workflows yet.
