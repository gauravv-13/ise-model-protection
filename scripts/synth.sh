#!/usr/bin/env bash
# Synthesize one design with Genus at TSMC 65 nm LP (typical corner).
#   scripts/synth.sh <design> [period_ns]        default period 4.0 ns
# designs:
#   cva6_base        CVA6 (cv64a6_imafdc_sv39) without Zkn
#   cva6_zkne        CVA6 with the four Zkne AES instructions            (Option A)
#   cva6_zkn         CVA6 with all of Zkn, as upstream (AES enc+dec, SHA-2, Zbkb/Zbkx)
#   engine_unmasked  OpenTitan AES without masking + DMA                 (Option B)
#   engine_masked    OpenTitan AES, default (masked, DOM S-box) + DMA
#   zkne_unit        CVA6's Zkn unit alone, Zkne instructions only (cross-check)
# CVA6's cache memories are black boxes: areas are logic only.
# Output: build/synth/<design>[_<period>ns]/ (reports); log in logs/.
# The library path is lab-specific; set SYN_LIB to override.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CVA6=$REPO_ROOT/third_party/cva6
OT=$REPO_ROOT/third_party/opentitan
design=${1:?usage: $0 <cva6_base|cva6_zkne|cva6_zkn|engine_unmasked|engine_masked|zkne_unit> [period_ns]}
export SYN_PERIOD=${2:-4.0}
export SYN_LIB=${SYN_LIB:-/eda/pdk/mybox-selected/Standard_Cell/core_cell_library/9-track/tcbn65lp_220a/FE/NLDM_extracted/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a/tcbn65lptc.lib}
tag=$design$([ "$SYN_PERIOD" = 4.0 ] || echo "_${SYN_PERIOD}ns")
export SYN_OUT=$REPO_ROOT/build/synth/$tag
mkdir -p "$SYN_OUT" "$REPO_ROOT/logs"
export SYN_FILES=$SYN_OUT/files.txt SYN_DEFINES=""

case $design in
  cva6_*)
    export SYN_TOP=cva6
    # The configuration is the stock one; only the Zkn switch differs.
    cfg=$SYN_OUT/cva6_config_pkg.sv
    cp "$CVA6/core/include/cv64a6_imafdc_sv39_config_pkg.sv" "$cfg"
    grep -q "ZKN: bit'(1)," "$cfg"
    if [ "$design" = cva6_base ]; then sed -i "s/ZKN: bit'(1),/ZKN: bit'(0),/" "$cfg"; fi
    if [ "$design" = cva6_zkne ]; then SYN_DEFINES="ZKNE_ONLY"; fi   # hw/patches/cva6/0004
    SYN_INCDIRS=$(python3 "$REPO_ROOT/hw/synth/cva6_files.py" "$CVA6" "$cfg" "$SYN_FILES")
    export SYN_INCDIRS
    ;;
  zkne_unit)
    export SYN_TOP=zkn_wrap
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
  engine_unmasked|engine_masked)
    export SYN_TOP=aes_$design
    python3 "$REPO_ROOT/hw/engine/gen_flist.py" "$OT" "$SYN_OUT/ot_aes.f" >/dev/null
    # Memory primitives (RAM/ROM/OTP/flash models) are not used by AES and
    # contain simulation-only code Genus cannot parse.
    { grep -v '^+incdir' "$SYN_OUT/ot_aes.f" \
        | awk '!(/\/prim(_generic)?_(ram|rom|otp|flash)[^\/]*\.sv$/ && !/_pkg\.sv$/)'
      echo "$REPO_ROOT/hw/engine/aes_dma.sv"
      echo "$REPO_ROOT/hw/engine/aes_engine.sv"
    } > "$SYN_FILES"
    export SYN_INCDIRS="$OT/hw/ip/prim/rtl $OT/hw/ip/tlul/rtl"
    ;;
  *) echo "unknown design: $design" >&2; exit 1 ;;
esac

log=$REPO_ROOT/logs/synth_$tag.log
echo ">> Genus: $design (top $SYN_TOP, ${SYN_PERIOD} ns), log: logs/synth_$tag.log"
(cd "$SYN_OUT" && nice -n 10 genus -batch -no_gui -files "$REPO_ROOT/hw/synth/synth.tcl" > "$log" 2>&1) \
    || { grep -E '^Error|ERROR' "$log" | head -20; exit 1; }
grep -m1 -E "^\s*$SYN_TOP\s" "$SYN_OUT/area.rpt" || true
grep -m1 -E "Slack|slack" "$SYN_OUT/timing.rpt" || true
