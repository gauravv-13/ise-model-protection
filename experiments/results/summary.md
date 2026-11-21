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
| Tiny CNN | No protection (copy only) | 9,239 | 0 | 0.00 | 0 | - | - |
| Tiny CNN | Software AES (baseline) | 1,746,103 | 1,736,792 | 140.97 | 1,736,792 | 1.0x | 0.07x |
| Tiny CNN | A: Zkne instructions | 128,123 | 118,812 | 9.64 | 118,812 | 14.6x | 1.00x |
| Tiny CNN | B: OpenTitan AES + DMA, unmasked | 44,227 | 34,936 | 2.84 | 6,656 | 49.7x | 3.40x |
| Tiny CNN | B: OpenTitan AES + DMA, masked | 103,451 | 94,160 | 7.64 | 7,240 | 18.4x | 1.26x |
| MLP 784-128-10 | No protection (copy only) | 74,643 | 0 | 0.00 | 0 | - | - |
| MLP 784-128-10 | Software AES (baseline) | 14,481,407 | 14,406,067 | 140.86 | 14,406,067 | 1.0x | 0.07x |
| MLP 784-128-10 | A: Zkne instructions | 1,054,765 | 979,425 | 9.58 | 979,425 | 14.7x | 1.00x |
| MLP 784-128-10 | B: OpenTitan AES + DMA, unmasked | 349,073 | 273,852 | 2.68 | 40,600 | 52.6x | 3.58x |
| MLP 784-128-10 | B: OpenTitan AES + DMA, masked | 840,078 | 764,863 | 7.48 | 44,675 | 18.8x | 1.28x |
| MLP 784-1024-256-10 | No protection (copy only) | 782,399 | 0 | 0.00 | 0 | - | - |
| MLP 784-1024-256-10 | Software AES (baseline) | 151,768,347 | 150,978,922 | 140.73 | 150,978,922 | 1.0x | 0.07x |
| MLP 784-1024-256-10 | A: Zkne instructions | 11,066,791 | 10,277,056 | 9.58 | 10,277,056 | 14.7x | 1.00x |
| MLP 784-1024-256-10 | B: OpenTitan AES + DMA, unmasked | 3,660,471 | 2,872,046 | 2.68 | 425,488 | 52.6x | 3.58x |
| MLP 784-1024-256-10 | B: OpenTitan AES + DMA, masked | 8,811,526 | 8,021,541 | 7.48 | 466,894 | 18.8x | 1.28x |

## Tile size (100 KB model): check + decrypt, cycles/byte

| Tile | A: Zkne | B: engine | B: engine, masked |
|---:|---:|---:|---:|
| 1,024 B | 10.19 | 3.96 | 8.90 |
| 4,096 B | 9.58 | 2.68 | 7.48 |
| 16,384 B | 9.44 | 2.37 | 7.13 |
| 65,536 B | 9.40 | 2.28 | 7.04 |

## Area and timing (65 nm LP, logic only)

| Design | Clock (ns) | Area (um^2) | kGE | Slack (ns) |
|---|---:|---:|---:|---:|
| cva6_base | 4 | 538,305 | 373.8 | +0.000 |
| cva6_base | 2.5 | 578,199 | 401.5 | +0.000 |
| cva6_zkn | 4 | 546,022 | 379.2 | +0.000 |
| cva6_zkne | 4 | 547,860 | 380.5 | +0.000 |
| cva6_zkne | 2.5 | 575,557 | 399.7 | +0.000 |
| dma | 4 | 19,927 | 13.8 | +1.446 |
| engine_masked | 4 | 152,730 | 106.1 | +0.000 |
| engine_unmasked | 4 | 74,458 | 51.7 | +0.000 |
| zkne_unit | 4 | 8,520 | 5.9 | +1.211 |

## Cost model, fitted to the measurements

Check + decrypt cycles = a x (16-byte blocks) + b x (tiles), least squares over all runs.

| Method | a: cycles per block | cycles per byte | b: cycles per tile |
|---|---:|---:|---:|
| Software AES (baseline) | 2239.0 | 139.94 | 3,267 |
| A: Zkne instructions | 150.1 | 9.38 | 824 |
| B: OpenTitan AES + DMA, unmasked | 36.0 | 2.25 | 1,753 |
| B: OpenTitan AES + DMA, masked | 112.0 | 7.00 | 1,945 |

Option A (proposal model T_A = N_blk x (2 R k CPI + c_ovh), 2 R k = 40): 142.3 instructions per block at CPI 1.08; the 40 AES instructions take 43 cycles, so c_ovh = 110 cycles per block (44 round-key loads, 44 XORs, data load/store, counter).

B: OpenTitan AES + DMA, unmasked (T_B = max(S/BW_mem, N_blk/Theta_eng) + c_setup): the engine takes 18.2 cycles per block per pass (Theta_eng = 1/18.2), two passes (CMAC, then CTR); c_setup = 1,624 CPU cycles per tile. Memory is not the limit: a DMA copy takes 0.36 cycles per byte (BW_mem = 2.8 bytes per cycle).

B: OpenTitan AES + DMA, masked (T_B = max(S/BW_mem, N_blk/Theta_eng) + c_setup): the engine takes 56.3 cycles per block per pass (Theta_eng = 1/56.3), two passes (CMAC, then CTR); c_setup = 1,782 CPU cycles per tile. Memory is not the limit: a DMA copy takes 0.36 cycles per byte (BW_mem = 2.8 bytes per cycle).

## Break-even

- Time: B: engine is faster than Zkne once a tile has more than 8 blocks (130 bytes); for large tiles it is 4.17x faster.
- Time: B: engine, masked is faster than Zkne once a tile has more than 29 blocks (472 bytes); for large tiles it is 1.34x faster.
- Area: Zkne adds 6.6 kGE to CVA6 (1.77 % of the 374 kGE core logic); the unmasked engine with DMA is 51.7 kGE, 7.8x as much.
  - A: Zkne: 16.1 bytes per 1000 cycles per added kGE
  - B: engine: 8.6 bytes per 1000 cycles per added kGE
  - B: engine, masked: 1.3 bytes per 1000 cycles per added kGE
- CPU: with Zkne the CPU does all the work, 9.38 cycles per byte. At 250 MHz that is 26.7 MB/s with the whole CPU, 2.67 MB/s with 10 % of it. Beyond that load rate (model size x reloads per second) the engine is the only option.
