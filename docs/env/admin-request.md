# Draft: tool request for the lab admin

*Draft only. Gaurav decides what to send. Updated 2026-10-20. Nothing here blocks the
project: user-local builds and VCS cover everything for now.*

---

Subject: Small tool request for the lab workstation (RISC-V)

Hello,

I'm starting my honours project on RISC-V SoC security, using the open-source Carfield
SoC from the PULP platform. Thank you for the shared EDA setup in /eda. VCS, Genus,
Joules, PrimeTime, the xPack RISC-V GCC and the 65 nm libraries all work for me, and
I've put my project-specific tools in my own home directory.

A few small things would help other lab users too:

1. **Joules on PATH.** Joules is installed and licensed
   (`/eda/tools/cadence/DDI251/JSTUDIO251/bin/joules`), but /eda/env/eda.sh doesn't add
   it to PATH.
2. **Spike (riscv-isa-sim)**, the reference RISC-V instruction-set simulator, and
   **dtc** (device-tree compiler), which Spike needs. I've built both in my home for
   now; a shared install would save others the build.
3. **Optional: Cadence Xcelium.** The Cadence server already has Xcelium licences, but
   the simulator isn't installed. I don't need it (VCS works), but others might.

Thank you very much.

Best regards,
Gaurav
