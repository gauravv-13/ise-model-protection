# Lab workstation: environment check

First checked 2026-10-16 and updated 2026-10-20. Licence server addresses are
deliberately left out of this file.

## Machine

| Item | Value |
|------|-------|
| OS | Red Hat Enterprise Linux 9.8, kernel 7.2.3 (elrepo), glibc 2.34 |
| CPU | AMD Ryzen Threadripper 9970X, 32 cores / 64 threads |
| RAM | 30 GiB, plus 15 GiB swap (often 20+ GiB in use by other users) |
| `/home` (my home is here) | 1.2 TB disk, **shared by all users**; 145 GB free (89 % used) on 2026-10-20, down from 265 GB on 10-16 |
| Quota | none set (`quota -s` prints nothing) |
| `/` (also holds `/tmp`) | 70 GB, 48 GB free, shared |
| Scratch disk I own | **none**. There are no `/scratch`, `/data` or `/local` disks. `/tools` is world-writable but belongs to the lab, so we don't use it. |

What this means for us:
- RAM, not CPU, is the tight resource. Check `free -h` before big builds or
  simulations, and keep builds at `-j4`.
- `/home` is shared and filling up, so keep downloads lean.

## How the lab provides tools

- The lab does **not** use environment modules for EDA tools. `module avail`
  shows only the default system modulefiles (Modules 5.3.0).
- Every login shell runs `/etc/profile.d/eda.sh`, and that sources `/eda/env/eda.sh`
  (root-owned). This puts every EDA tool on PATH and sets the Cadence and Synopsys
  licence variables. Nothing needs loading by hand. A terminal opened before a
  lab change keeps the old settings, so open a new one.
- `/eda` is a link to `/home/eda`, and everything under it is read-only for users.
  The lab guide is `/eda/README.md`, with per-tool notes in `/eda/tools/synopsys/NOTES.md`.
- The TSMC PDKs in `/eda/pdk` are under a foundry NDA. Never copy them off this
  machine or into the repo.

## Tools

| Tool | Status | Path | Version | How it is loaded |
|------|--------|------|---------|------------------|
| git | OK | /usr/bin/git | 2.52.0 | system |
| make | OK | /usr/bin/make | GNU Make 4.3 | system |
| gcc / g++ (host) | OK | /usr/bin/gcc | 11.5.0 | system |
| flex, bison, autoconf | OK | /usr/bin | | system |
| python3 | OK (old) | /usr/bin/python3 | 3.9.25, the only version installed | system |
| venv | OK | `python3 -m venv` works | | system |
| pip (system), conda | missing | | | use a venv |
| cargo / rustc | missing | | | not needed (Bender is prebuilt) |
| bender | **installed user-local** | ~/tools/bin/bender -> ~/tools/bender/0.32.1/bender | 0.32.1 (prebuilt release, SHA-256 checked) | `~/tools/bin` on PATH |
| dtc | missing on the system | | | building user-local (needed by Spike) |
| spike | missing on the system | | | building user-local |
| cmake, ninja | missing | | | not needed yet |
| RISC-V GCC (rv64 + rv32) | **OK** | /eda/tools/opensource/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc | xPack GCC 15.2.0 | lab env (appended to PATH) |
| `riscv64-unknown-elf-*` names | missing | | | xPack uses the `riscv-none-elf-` prefix instead (see below) |
| iverilog | OK (too limited for Carfield) | /eda/bin/iverilog | 13.0 | lab env |
| **VCS** | **OK, licence works** | /eda/tools/synopsys/vcs/U-2023.03/bin/vcs | U-2023.03 | lab env; always run as `vcs -full64` |
| DVE (waveforms), vlogan, urg | OK | /eda/tools/synopsys/vcs/U-2023.03/bin | U-2023.03 | lab env |
| QuestaSim (vsim) | missing; VCS replaces it | not anywhere on disk; no Siemens licence variables | | |
| Xcelium (xrun) | not installed (licensed on the Cadence server); optional | | | not needed: VCS replaces it |
| Verilator | missing; VCS replaces it | | | |
| Verdi | missing | | | DVE is enough; Cheshire's VCS script passes `-kdb` (a Verdi option) |
| Synopsys DC / ICC2 / LC / Formality | OK | /eda/bin, /eda/tools/synopsys | DC T-2022.03-SP5 (runs in a RHEL 8 container), ICC2 U-2022.12-SP3, LC X-2025.06-SP3, FM X-2025.06-SP4 | lab env |
| PrimeTime | OK (added 2026-10-18) | /eda/bin/pt_shell | U-2022.12-SP3 | lab env; prints one harmless `MEM Error` at startup |
| Cadence Genus | **OK, licence works** | /eda/tools/cadence/DDI251/GENUS251/bin/genus | 25.10-p002_1 | lab env |
| Cadence Joules (RTL/gate power) | **OK, licence works, not on PATH** | /eda/tools/cadence/DDI251/bin/joules | 25.10-p002_1 | full path, or add `/eda/tools/cadence/DDI251/JSTUDIO251/bin` to PATH |
| Cadence Innovus / Virtuoso / Modus / Pegasus | OK | /eda/tools/cadence | DDI 25.1, IC 25.1 | lab env |
| Tempus, Voltus, Jasper, Conformal | not installed (licensed) | | | not needed |
| Vivado | missing | no install, no `XILINX*` variables | | FPGA stretch goal only |
| podman | OK | /usr/bin/podman | 5.8.2 | system |
| GitHub | OK | HTTPS and SSH both work | | |

### RISC-V GCC and Zkne: tested

A tiny C file with inline `aes64esm`, `aes64ks1i` and `aes64ks2`, built with
`riscv-none-elf-gcc -march=rv64gc_zkne -mabi=lp64d`, compiles and links (newlib), and
`objdump` shows the AES instructions. The `riscv_crypto.h` intrinsics header is
present. `-march=rv32imc -mabi=ilp32` also links. **So the lab's compiler is new enough;
we don't need our own CVA6 toolchain.**

Notes for later:
- Cheshire/Carfield Makefiles expect the prefix `riscv64-unknown-elf-`. With xPack we
  either pass the compiler path to make, or put `riscv64-unknown-elf-*` symlinks
  pointing at the `riscv-none-elf-*` binaries in `~/tools/bin`.
- The PULP integer cluster software needs the PULP GCC (Xpulp extensions), and Spatz
  needs its own LLVM. Neither is on the machine; both are needed in phase 2, not now.

### VCS: tested

A one-module SystemVerilog test compiled, linked and ran in about 7 s, so the Synopsys
licence is reachable. Running VCS creates a small hidden licence-cache file in `~`
whose name contains the server address. Harmless, but never commit it.

## Simulation without QuestaSim

Carfield's own RTL simulation flow supports **only QuestaSim**: in upstream
`target/sim/sim.mk` the VCS and Xcelium sections are empty `# TODO` placeholders.
QuestaSim is not on this machine. **VCS replaces it:**
- Cheshire, the host-domain platform Carfield is built on, has an **official VCS flow**
  (`target/sim/vcs/`, script made by `bender script vcs`). **CVA6** has its own
  `vcs-testharness` and `vcs-uvm` flows. So CVA6 and the host domain (where the Zkne
  loader runs) can be simulated at RTL with VCS right away.
- The **full Carfield SoC** (clusters and security island) on VCS needs a port: Bender
  writes the VCS compile script, and we adapt Cheshire's VCS start script.
- Xcelium would need the same port, so it adds nothing for us. It's only a backup.

## Synthesis, power and the PDKs

- **Genus 25.1** and **Joules 25.1** both start and check out licences
  (`Genus_Synthesis`, `Joules_RTL_Power`). Design Compiler, Innovus and PrimeTime are
  also installed.
- `/eda/pdk` has the **TSMC 65 nm LP** standard-cell library (`tcbn65lp`): `.lib` and
  `.db` for all corners, and LEF for 6–9 metal layers. There are also MC2 SRAM and
  register-file compilers, but only the admin account can generate macros.
- `/eda/pdk/sky130` has the open **SkyWater SKY130** PDK (added by 2026-10-18), useful if
  anyone outside the lab needs to reproduce our numbers.
- So area (µm², kGE), Fmax and per-cycle power traces can come from 65 nm synthesis
  plus Joules, without an FPGA. Never copy TSMC files into the repo; report only numbers.
