# hw/rtl/aes_periph

OpenTitan's AES block as a memory-mapped peripheral of the CVA6 test harness, so
a real CPU drives it.

    CVA6 --AXI--> axi2apb_64_32 --APB--> aes_periph.sv --TL-UL--> OpenTitan aes

- `aes_periph.sv`: APB to TL-UL (with OpenTitan's bus integrity code), a stand-in
  entropy source for the masking PRNG, and tie-offs (no key manager, no alerts).
  AES keeps OpenTitan's defaults (masked, DOM S-box), as in Carfield's security island.
- `gen_flist.py`: VCS/Genus file list for the AES block, taken from OpenTitan's
  `Bender.yml` in the Carfield checkout. CVA6 also has a module `aes` and a package
  `aes_pkg`, so the OpenTitan AES files are copied with those names changed to
  `ot_aes` / `ot_aes_pkg`. The checkout itself is not changed.

Built by `scripts/cva6_sim.sh build`. Register use: `sw/tests/aes_compare/aes_ot.c`.

Limits: the entropy stand-in is an LFSR (one word per 4 cycles, faster than a real
EDN). In Carfield, CVA6 reaches the island through more bridges than here.
