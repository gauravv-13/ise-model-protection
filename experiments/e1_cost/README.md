# experiments/e1_cost

E1: Cost of AES-128 encryption on CVA6: software vs Zkne instructions vs the
OpenTitan AES accelerator. Speed (cycles), area and slack (Genus, 65 nm) and
energy per block (Joules).

Re-create everything (about 1 hour on the workstation):

    source env/setup.sh
    scripts/setup_cva6.sh && scripts/cva6_sim.sh build
    make -C sw/tests/aes_compare PLATFORM=cva6 MAX_BYTES=4096
    scripts/cva6_sim.sh run sw/tests/aes_compare/build/cva6/aes_compare.elf
    for d in zkne zkn ot_masked ot_unmasked; do scripts/synth.sh $d; done
    experiments/e1_cost/scripts/run_power.sh
    .venv/bin/python experiments/e1_cost/scripts/report.py

`results/summary.md` is the table; `results/*.png` the charts.
