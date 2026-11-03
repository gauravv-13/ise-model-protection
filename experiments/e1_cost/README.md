# experiments/e1_cost

E1: Cost of AES-128 encryption on CVA6: software vs Zkne instructions vs the
OpenTitan AES accelerator. Speed (cycles) and area and slack (Genus, 65 nm).

Re-create everything (about 1.5 hours on the workstation, mostly synthesis):

    source env/setup.sh
    scripts/setup_cva6.sh && scripts/cva6_sim.sh build
    make -C sw/tests/aes_compare PLATFORM=cva6 MAX_BYTES=4096
    scripts/cva6_sim.sh run sw/tests/aes_compare/build/cva6/aes_compare.elf
    for d in zkne zkn ot_masked ot_unmasked; do scripts/synth.sh $d; done
    scripts/synth.sh zkne 1.0
    .venv/bin/python experiments/e1_cost/scripts/report.py

`results/summary.md` is the table; `results/*.png` the charts.

Energy (not run yet, waiting on advisor feedback): `scripts/run_power.sh` records
switching activity of each block in VCS and runs Joules. It only counts the AES
hardware, not CVA6's own energy, so read its numbers with that in mind.
