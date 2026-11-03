#!/usr/bin/env bash
# Synthesize one AES block with Genus at TSMC 65 nm LP (typical corner).
#   scripts/synth.sh <design> [period_ns]
# designs: zkne         CVA6 Zkn unit, only the 4 Zkne encryption instructions
#          zkn          CVA6 Zkn unit, all instructions (enc, dec, SHA-2)
#          ot_masked    OpenTitan AES, default (masked, DOM S-box), as in Carfield
#          ot_unmasked  OpenTitan AES without masking
# Output: build/synth/<design>[_<period>ns]/ (reports, netlist); log in logs/.
# The library path is lab-specific; set SYN_LIB to override.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CVA6=$REPO_ROOT/third_party/cva6
OT=$(cd "$REPO_ROOT/third_party/carfield" && bender path opentitan)
design=${1:?usage: $0 <zkne|zkn|ot_masked|ot_unmasked> [period_ns]}
export SYN_PERIOD=${2:-2.0}
export SYN_LIB=${SYN_LIB:-/eda/pdk/mybox-selected/Standard_Cell/core_cell_library/9-track/tcbn65lp_220a/FE/NLDM_extracted/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a/tcbn65lptc.lib}
tag=$design$([ "$SYN_PERIOD" = 2.0 ] || echo "_${SYN_PERIOD}ns")
export SYN_OUT=$REPO_ROOT/build/synth/$tag
mkdir -p "$SYN_OUT" "$REPO_ROOT/logs"
export SYN_FILES=$SYN_OUT/files.txt

case $design in
  zkne|zkn)
    if [ "$design" = zkn ]; then export SYN_TOP=zkn_full; else export SYN_TOP=zkn_wrap; fi
    # CVA6 packages in Flist.cva6 order, then the Zkn unit and our wrapper.
    {
      for f in core/cvfpu/src/fpnew_pkg.sv core/include/config_pkg.sv \
               core/include/cv64a6_imafdc_sv39_config_pkg.sv core/include/riscv_pkg.sv \
               core/include/ariane_pkg.sv core/include/build_config_pkg.sv \
               core/include/aes_pkg.sv core/aes.sv; do
          echo "$CVA6/$f"
      done
      echo "$REPO_ROOT/hw/synth/zkn_wrap.sv"
    } > "$SYN_FILES"
    export SYN_INCDIRS="$CVA6/core/include $CVA6/vendor/pulp-platform/common_cells/include"
    ;;
  ot_masked|ot_unmasked)
    export SYN_TOP=ot_aes
    python3 "$REPO_ROOT/hw/rtl/aes_periph/gen_flist.py" "$OT" "$SYN_OUT/ot_aes.f" >/dev/null
    # Memory primitives (RAM/ROM/OTP/flash models) are not used by AES and
    # contain simulation-only code Genus cannot parse.
    grep -v '^+incdir' "$SYN_OUT/ot_aes.f" \
        | awk '!(/\/prim(_generic)?_(ram|rom|otp|flash)[^\/]*\.sv$/ && !/_pkg\.sv$/)' > "$SYN_FILES"
    if [ "$design" = ot_unmasked ]; then
        SYN_TOP=ot_aes_unmasked
        echo "$REPO_ROOT/hw/synth/ot_aes_unmasked.sv" >> "$SYN_FILES"
    fi
    export SYN_INCDIRS="$OT/hw/ip/prim/rtl $OT/hw/ip/tlul/rtl"
    ;;
  *) echo "unknown design: $design" >&2; exit 1 ;;
esac

# Save the settings for scripts/power.sh, which reuses the file lists.
declare -p SYN_TOP SYN_FILES SYN_INCDIRS SYN_LIB | sed 's/^declare -x/export/' > "$SYN_OUT/env.sh"
[ -n "${SYNTH_ONLY_FILES:-}" ] && exit 0

log=$REPO_ROOT/logs/synth_$tag.log
echo ">> Genus: $design (top $SYN_TOP, ${SYN_PERIOD} ns), log: logs/synth_$tag.log"
(cd "$SYN_OUT" && nice -n 10 genus -batch -no_gui -files "$REPO_ROOT/hw/synth/synth.tcl" > "$log" 2>&1) \
    || { grep -E '^Error|ERROR' "$log" | head -20; exit 1; }
grep -E "^\s*$SYN_TOP|^ *Instance" "$SYN_OUT/area.rpt" | head -3 || true
grep -m1 -E "Slack|slack" "$SYN_OUT/timing.rpt" || true
