# Project context

Protecting neural-network models on a RISC-V SoC using the host CPU's own AES instructions (RISC-V Zkne on CVA6) instead of the on-chip security engine. The CVA6 host decrypts (AES-CTR) and checks (AES-CMAC) every model block (weights, layer descriptors, and kernel code) before PULP accelerator clusters use it. We compare area, load latency, and CPU cost against Carfield's OpenTitan-based security island, and test against bit-flip (RowHammer-style) and power side-channel attacks. Platform: PULP's Carfield SoC. Honours research project, IIIT Hyderabad.

## Conventions
- Run heavy workloads (Carfield builds, toolchains, RTL simulation, synthesis) on the shared Linux workstation.
- Keep large files and generated bulk artifacts outside this repository.
- Use at most `-j8` for parallel builds.
- Ask before triggering large downloads.
