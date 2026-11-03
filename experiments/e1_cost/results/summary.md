# AES-128 on CVA6: software vs Zkne vs OpenTitan accelerator

All numbers from RTL simulation (VCS) of upstream CVA6 and synthesis
(Genus/Joules) at TSMC 65 nm LP, typical corner (1.2 V, 25 C).

## Speed (cycles on CVA6)

| Method | Key setup | 1 block (16 B) | 1 KB | 4 KB | Cycles/block (4 KB) | Speed-up vs software |
|---|---:|---:|---:|---:|---:|---:|
| Software (T-table) | 2,508 | 1,146 | 72,465 | 289,144 | 1129.5 | 1.0x |
| Zkne instructions | 194 | 141 | 6,764 | 27,436 | 107.2 | 10.5x |
| OpenTitan AES accelerator | 312 | 206 | 6,078 | 24,223 | 94.6 | 11.9x |

## Area and timing (65 nm)

| Block | Clock target | Area (um^2) | kGE | Logic only, no registers (kGE) | Worst slack (ns) |
|---|---:|---:|---:|---:|---:|
| Zkne unit (4 encryption instructions) | 2 ns (500 MHz) | 8,785 | 6.1 | 4.9 | 0.000 |
| Full Zkn unit in CVA6 (enc+dec+SHA-2) | 2 ns (500 MHz) | 16,751 | 11.6 | 10.4 | 0.000 |
| OpenTitan AES, masked (Carfield default) | 2 ns (500 MHz) | 141,457 | 98.2 | 59.6 | 0.000 |

Zkne/Zkn rows include 201-204 wrapper registers that stand in for CVA6's
existing pipeline registers; the 'logic only' column leaves them out.
Slack >= 0 means the block meets that clock; negative slack is how much too slow.

## Energy per 16-byte block (AES hardware only)

| Block | Dynamic (pJ) | Leakage at 500 MHz (pJ) | Total (pJ) |
|---|---:|---:|---:|

Dynamic energy = (energy of the 4 KB run - energy of the 16 B run) / 255, so
boot, key setup and the accelerator's reset-time reseeding cancel out.
Not included: the CPU's own energy (CVA6 is busy ~107 cycles/block with Zkne,
and mostly waiting on the bus with the accelerator).

