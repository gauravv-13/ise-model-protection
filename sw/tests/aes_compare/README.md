# sw/tests/aes_compare

AES-128 encryption three ways, bare metal, with cycle counts:

| File | Method |
|---|---|
| `aes_sw.c` | Software, T-tables (what a library does without AES instructions) |
| `aes_zkne.c` | RISC-V Zkne: `aes64ks1i`, `aes64ks2`, `aes64esm`, `aes64es` |
| `aes_ot.c` | OpenTitan AES accelerator at `0x4000_0000` (CVA6 harness only) |

`main.c` checks each against FIPS-197 C.1 (key `000102…0f`, pt `00112233…ff`,
ct `69c4e0d8…c55a`), encrypts 16 B / 1 KB / 4 KB buffers and prints `RESULT` lines
with `mcycle`/`minstret` counts. All methods must produce the same ciphertext.

    make spike                                   # Spike, sw + zkne
    make PLATFORM=cva6 MAX_BYTES=4096            # CVA6 harness, all three
    scripts/cva6_sim.sh run sw/tests/aes_compare/build/cva6/aes_compare.elf
    make PLATFORM=cva6 ONLY=zkne MAX_BYTES=4096  # one method only (power runs)

On Spike every instruction counts as one cycle; only CVA6 gives real cycles.
