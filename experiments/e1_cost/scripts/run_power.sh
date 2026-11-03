#!/usr/bin/env bash
# Energy runs for E1: switching activity of the Zkn unit and of the OpenTitan
# AES block while CVA6 encrypts 16 B and 4096 B (one method per program), then
# Joules on each. Energy per block = difference of the two runs / 255.
# Needs scripts/cva6_sim.sh build first. Source env/setup.sh first.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$REPO_ROOT"
mkdir -p build/power

zkn_scope=ariane_tb.dut.i_ariane.i_cva6.ex_stage_i.aes_gen.aes_i
ot_scope=ariane_tb.dut.i_aes_periph.i_aes

for n in 16 4096; do
    make -s -C sw/tests/aes_compare PLATFORM=cva6 ONLY=zkne MAX_BYTES=$n
    make -s -C sw/tests/aes_compare PLATFORM=cva6 ONLY=ot   MAX_BYTES=$n
    scripts/cva6_sim.sh saif sw/tests/aes_compare/build/cva6_zkne_$n/aes_compare.elf $zkn_scope build/power/zkne_$n.saif &
    scripts/cva6_sim.sh saif sw/tests/aes_compare/build/cva6_ot_$n/aes_compare.elf   $ot_scope  build/power/ot_$n.saif &
done
wait

# Two Joules jobs at a time (shared machine).
for n in 16 4096; do
    scripts/power.sh zkn       build/power/zkne_$n.saif &
    scripts/power.sh ot_masked build/power/ot_$n.saif &
    wait
done
