#!/usr/bin/env bash
# Unit test of the AES engine (OpenTitan AES + DMA) on its own, in VCS.
#   scripts/engine_tb.sh [masked]
# Source env/setup.sh first; run scripts/setup_opentitan.sh once before.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
variant=${1:-unmasked}
out=$REPO_ROOT/build/engine_tb/$variant
mkdir -p "$out" "$REPO_ROOT/logs"
cd "$out"
python3 "$REPO_ROOT/hw/engine/gen_flist.py" "$REPO_ROOT/third_party/opentitan" ot_aes.f >/dev/null
nice -n 10 vcs -full64 -sverilog -nc -q -assert svaext -timescale=1ns/1ps +lint=none \
    -f ot_aes.f "$REPO_ROOT"/hw/engine/aes_dma.sv "$REPO_ROOT"/hw/engine/aes_engine.sv \
    "$REPO_ROOT"/hw/engine/tb/aes_engine_tb.sv -top aes_engine_tb \
    -pvalue+aes_engine_tb.Masked="$([ "$variant" = masked ] && echo 1 || echo 0)" -o simv \
    > "$REPO_ROOT/logs/engine_tb_$variant.log" 2>&1 || { grep -A5 'Error-\[' "$REPO_ROOT/logs/engine_tb_$variant.log" | head -30; exit 1; }
./simv -q 2>&1 | tee -a "$REPO_ROOT/logs/engine_tb_$variant.log" | grep -v '^$'
