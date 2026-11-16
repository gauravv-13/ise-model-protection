# Results

RTL simulation (VCS) of upstream CVA6 with the AES engines on its AXI bus; synthesis with
Genus at TSMC 65 nm LP, typical corner (1.2 V, 25 C). Cycle counts are from the second of two
loads (warm caches) unless noted. Regenerate with `experiments/report.py`.

## Workloads

| Model | Weights (bytes) | Model blob (bytes) | Accuracy, float | Accuracy, int8 |
|---|---:|---:|---:|---:|
| Tiny CNN | 11,912 | 12,320 | 98.46 % | 98.51 % |
| MLP 784-128-10 | 101,632 | 102,264 | 97.76 % | 97.79 % |
| MLP 784-1024-256-10 | 1,067,520 | 1,072,792 | 97.97 % | 97.96 % |

## Model-load time (4 KB tiles)

Total = copy into L2 + check and decrypt + copy to L1. CPU busy = cycles the CPU itself works
on crypto (for the engine: set-up and tag check, not the wait).

| Model | Method | Total cycles | Check + decrypt | cycles/byte | CPU busy | vs software | vs Zkne |
|---|---|---:|---:|---:|---:|---:|---:|
| Tiny CNN | No protection (copy only) | 9,275 | 0 | 0.00 | 0 | - | - |
| Tiny CNN | Software AES (baseline) | 1,776,531 | 1,767,793 | 143.49 | 1,767,793 | 1.0x | 0.07x |
| Tiny CNN | A: Zkne instructions | 130,666 | 121,204 | 9.84 | 121,204 | 14.6x | 1.00x |
| Tiny CNN | B: OpenTitan AES + DMA, unmasked | 43,037 | 33,801 | 2.74 | 6,987 | 52.3x | 3.59x |
| Tiny CNN | B: OpenTitan AES + DMA, masked | 99,549 | 90,111 | 7.31 | 7,610 | 19.6x | 1.35x |
| MLP 784-128-10 | No protection (copy only) | 74,364 | 0 | 0.00 | 0 | - | - |
| MLP 784-128-10 | Software AES (baseline) | 14,737,184 | 14,661,163 | 143.35 | 14,661,163 | 1.0x | 0.07x |
| MLP 784-128-10 | A: Zkne instructions | 1,077,700 | 1,001,167 | 9.79 | 1,001,167 | 14.6x | 1.00x |
| MLP 784-128-10 | B: OpenTitan AES + DMA, unmasked | 340,195 | 266,769 | 2.61 | 42,123 | 55.0x | 3.75x |
| MLP 784-128-10 | B: OpenTitan AES + DMA, masked | 811,534 | 735,625 | 7.19 | 47,641 | 19.9x | 1.36x |
| MLP 784-1024-256-10 | No protection (copy only) | 786,106 | 0 | 0.00 | 0 | - | - |

## Tile size (100 KB model): check + decrypt, cycles/byte

| Tile | A: Zkne | B: engine | B: engine, masked |
|---:|---:|---:|---:|
| 1,024 B | 10.44 | 4.00 | 8.88 |
| 4,096 B | 9.79 | 2.61 | 7.19 |
| 16,384 B | 9.61 | 2.27 | 6.86 |
| 65,536 B | 9.55 | 2.17 | 6.72 |

## Area and timing (65 nm LP, logic only)

| Design | Clock (ns) | Area (um^2) | kGE | Slack (ns) |
|---|---:|---:|---:|---:|
| dma | 4 | 19,927 | 13.8 | +1.446 |
| engine_unmasked | 4 | 74,458 | 51.7 | +0.000 |

## Cost model, fitted to the measurements

Check + decrypt cycles = a x (16-byte blocks) + b x (tiles), least squares over all runs.

| Method | a: cycles per block | cycles per byte | b: cycles per tile |
|---|---:|---:|---:|
| Software AES (baseline) | 2287.1 | 142.94 | 1,684 |
| A: Zkne instructions | 152.7 | 9.55 | 918 |
| B: OpenTitan AES + DMA, unmasked | 34.2 | 2.14 | 1,900 |
| B: OpenTitan AES + DMA, masked | 106.8 | 6.68 | 2,244 |

Option A (proposal model T_A = N_blk x (2 R k CPI + c_ovh), 2 R k = 40): 142.3 instructions per block at CPI 1.10; the 40 AES instructions take 44 cycles, so c_ovh = 113 cycles per block (44 round-key loads, 44 XORs, data load/store, counter).

B: OpenTitan AES + DMA, unmasked (T_B = max(S/BW_mem, N_blk/Theta_eng) + c_setup): the engine takes 17.6 cycles per block per pass (Theta_eng = 1/17.6), two passes (CMAC, then CTR); c_setup = 1,685 CPU cycles per tile. Memory is not the limit: a DMA copy takes 0.36 cycles per byte (BW_mem = 2.7 bytes per cycle).

B: OpenTitan AES + DMA, masked (T_B = max(S/BW_mem, N_blk/Theta_eng) + c_setup): the engine takes 53.8 cycles per block per pass (Theta_eng = 1/53.8), two passes (CMAC, then CTR); c_setup = 1,906 CPU cycles per tile. Memory is not the limit: a DMA copy takes 0.36 cycles per byte (BW_mem = 2.7 bytes per cycle).

## Break-even

- Time: B: engine is faster than Zkne once a tile has more than 8 blocks (133 bytes); for large tiles it is 4.46x faster.
- Time: B: engine, masked is faster than Zkne once a tile has more than 29 blocks (462 bytes); for large tiles it is 1.43x faster.
- CPU: with Zkne the CPU does all the work, 9.55 cycles per byte. At 250 MHz that is 26.2 MB/s with the whole CPU, 2.62 MB/s with 10 % of it. Beyond that load rate (model size x reloads per second) the engine is the only option.
