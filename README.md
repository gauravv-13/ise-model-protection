# ISE-Based Model Protection for RISC-V AI Accelerators

Protecting neural-network models on a RISC-V SoC using the host CPU's own AES instructions (RISC-V Zkne on CVA6) instead of the on-chip security engine. The CVA6 host decrypts (AES-CTR) and checks (AES-CMAC) every model block (weights, layer descriptors, and kernel code) before PULP accelerator clusters use it. We compare area, load latency, and CPU cost against Carfield's OpenTitan-based security island, and test against bit-flip (RowHammer-style) and power side-channel attacks. Platform: PULP's Carfield SoC. Honours research project, IIIT Hyderabad.

## Folder guide
- `docs/`: Proposal material and paper/reference notes.
- `env/`: Local environment setup stubs and tool path setup.
- `hw/`: Hardware patches and custom RTL components.
- `sw/`: Loader, drivers, kernels, and software test vectors.
- `models/`: Model training/quantization and export pipelines.
- `tools/`: Encryption/packing and attack-analysis utilities.
- `sim/`: Simulation entry points for spike and RTL flows.
- `fpga/`: FPGA-related stretch-goal artifacts.
- `experiments/`: Reproducible experiment configs, scripts, and results.
- `paper/`: Manuscript assets and writing workspace.

## Getting started
