#!/usr/bin/env bash
# Run every model-load measurement in RTL simulation (VCS) and collect the logs.
#   experiments/run_sweep.sh [jobs]      default 6 simulations at a time
# Needs: env/setup.sh sourced, scripts/cva6_sim.sh build done, models trained
# (models/train.py). Logs: logs/run_<model>_t<tile>_<method>.log. The software
# AES run of the 1 MB model alone takes about 2.5 hours.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JOBS=${1:-6}
cd "$REPO_ROOT"

runs=()
add() {   # model method tile reps nn_images
    make -s -C sw/loader PLATFORM=cva6 MODEL=$1 METHOD=$2 TILE=$3 REPS=$4 NN_IMAGES=$5 >/dev/null
    runs+=("$1_t$3_$2")
}

# Main sweep: three model sizes, five methods, 4 KB tiles. Each load is run
# twice (cold, then warm). One test image is run on the loaded model for the
# ISE and the engine; the software loader is checked on Spike instead.
for model in cnn mlp_s mlp_l; do
    add $model none  4096 2 0
    add $model zkne  4096 2 1
    add $model eng_u 4096 2 1
    add $model eng_m 4096 2 1
    add $model sw    4096 $([ $model = mlp_l ] && echo 1 || echo 2) 0
done
# Tile-size sweep on the 100 KB model: per-tile setup cost of the engine.
for tile in 1024 16384 65536; do
    for method in zkne eng_u eng_m; do add mlp_s $method $tile 2 0; done
done

printf '%s\n' "${runs[@]}" | xargs -P "$JOBS" -I{} \
    scripts/cva6_sim.sh run build/sw/cva6/{}/loader.elf {} > logs/sweep.out 2>&1
grep -c "ALL PASS" logs/run_*_t*_*.log | sed 's/^/  /'
