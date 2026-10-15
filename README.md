# ISE-Based Model Protection for RISC-V AI Accelerators

Protecting neural-network models on a RISC-V SoC using the host CPU's own AES instructions (RISC-V Zkne on CVA6) instead of the on-chip security engine. The CVA6 host decrypts with AES-CTR and checks with AES-CMAC every model block—weights, layer descriptors, and kernel code—before PULP accelerator clusters use it. Compare area, load latency, and CPU cost against Carfield's OpenTitan-based security island, and test against bit-flip (RowHammer-style) and power side-channel attacks. Platform: PULP's Carfield SoC. Honours research project, IIIT Hyderabad.

## Folder guide
- `docs/`: proposal drafts, advisor meeting notes, and reference/paper notes.
- `env/`: environment stubs for local and workstation setup.
- `hw/`: hardware patch notes and custom RTL research components.
- `sw/`: loader, drivers, kernels, and software-side test vectors.
- `models/`: training/quantization flow and model export notes.
- `tools/`: utilities for encryption, bit-flip testing, and leakage analysis.
- `sim/`: simulator-specific setup notes for Spike and RTL runs.
- `fpga/`: FPGA-oriented bring-up and stretch-goal notes.
- `experiments/`: configs, scripts, and results for core experiment tracks.
- `paper/`: paper writing and publication artifacts.

## Getting started
