#!/usr/bin/env bash
# Energy runs for E1. For each block (the Zkn unit, the OpenTitan AES block),
# record switching activity while CVA6 runs one method on 16 B and on 4096 B,
# and the same start-up with no encryption (ONLY=none), then Joules on each.
# Energy per block = [(E_4096 - E_16) - (E_none4096 - E_none16)] / 255,
# which removes boot, key setup and the buffer fill (see report.py).
# Needs scripts/cva6_sim.sh build first. Source env/setup.sh first.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$REPO_ROOT"
mkdir -p build/power

zkn_scope=ariane_tb.dut.i_ariane.i_cva6.ex_stage_i.aes_gen.aes_i
ot_scope=ariane_tb.dut.i_aes_periph.i_aes
elf() { echo "sw/tests/aes_compare/build/cva6_$1_$2/aes_compare.elf"; }

# 1. Programs and activity files (simulations are light: 4 at a time).
for n in 16 4096; do
    for o in zkne ot none; do
        make -s -C sw/tests/aes_compare PLATFORM=cva6 ONLY=$o MAX_BYTES=$n
    done
    scripts/cva6_sim.sh saif "$(elf zkne $n)" $zkn_scope build/power/zkne_$n.saif  >/dev/null &
    scripts/cva6_sim.sh saif "$(elf none $n)" $zkn_scope build/power/nonez_$n.saif >/dev/null &
    scripts/cva6_sim.sh saif "$(elf ot $n)"   $ot_scope  build/power/ot_$n.saif    >/dev/null &
    scripts/cva6_sim.sh saif "$(elf none $n)" $ot_scope  build/power/noneo_$n.saif >/dev/null &
    wait
done

# 2. Joules, two jobs at a time (shared machine).
for n in 16 4096; do
    scripts/power.sh zkn build/power/zkne_$n.saif & scripts/power.sh zkn build/power/nonez_$n.saif & wait
    scripts/power.sh ot_masked build/power/ot_$n.saif & scripts/power.sh ot_masked build/power/noneo_$n.saif & wait
done
