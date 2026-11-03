#!/usr/bin/env bash
# Power of one AES block with Joules, from a SAIF of the CVA6 run.
#   scripts/power.sh <zkn|ot_masked> <run.saif>
# Output: build/power/<design>_<saif name>/ ; log in logs/.
# zkn uses the full Zkn unit, because that is what CVA6 contains.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
design=${1:?usage: $0 <zkn|ot_masked> <run.saif>}
saif=$(readlink -f "${2:?missing SAIF}")
name=${design}_$(basename "$saif" .saif)
export PWR_OUT=$REPO_ROOT/build/power/$name PWR_SAIF=$saif PWR_PERIOD=${PWR_PERIOD:-20}
mkdir -p "$PWR_OUT"

# Same file lists as synthesis: let synth.sh write them, without running Genus.
SYNTH_ONLY_FILES=1 "$REPO_ROOT/scripts/synth.sh" "$design" >/dev/null
source "$REPO_ROOT/build/synth/$design/env.sh"

case $design in
  zkn)       export PWR_DUT=ariane_tb/dut/i_ariane/i_cva6/ex_stage_i/aes_gen/aes_i
             export PWR_ROOT=zkn_full/i_zkn/i_aes ;;
  ot_masked) export PWR_DUT=ariane_tb/dut/i_aes_periph/i_aes
             export PWR_ROOT=ot_aes ;;
  *) echo "unknown design: $design" >&2; exit 1 ;;
esac

log=$REPO_ROOT/logs/power_$name.log
echo ">> Joules: $name, log: logs/power_$name.log"
(cd "$PWR_OUT" && nice -n 10 joules -batch -no_gui -files "$REPO_ROOT/hw/synth/power.tcl" > "$log" 2>&1) \
    || { grep -E '^Error|ERROR' "$log" | head -20; exit 1; }
grep -E "Subtotal|Total|$PWR_ROOT|i_aes" "$PWR_OUT/power_hier.rpt" | head -8 || true
