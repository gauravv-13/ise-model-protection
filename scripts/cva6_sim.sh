#!/usr/bin/env bash
# Build and run upstream CVA6 (third_party/cva6) with the AES engines in VCS.
#   scripts/cva6_sim.sh build            compile the test harness (simv)
#   scripts/cva6_sim.sh run <prog.elf> [log name]
#                                        run a bare-metal program, log in logs/
# Source env/setup.sh first. Run scripts/setup_cva6.sh and
# scripts/setup_opentitan.sh once before.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CVA6_DIR=$REPO_ROOT/third_party/cva6
OT_DIR=$REPO_ROOT/third_party/opentitan
SPIKE_DIR=${SPIKE_DIR:-$(dirname "$(dirname "$(readlink -f "$(command -v spike)")")")}
LOGS=$REPO_ROOT/logs
mkdir -p "$LOGS"

# The CVA6 Makefile reads these.
export RISCV=$SPIKE_DIR SPIKE_INSTALL_DIR=$SPIKE_DIR CVA6_REPO_DIR=$CVA6_DIR

build() {
    cd "$CVA6_DIR"
    # DPI library (ELF loader, debug-module stubs) + our stand-ins for core-v-verif.
    # Linked by hand: upstream also links yaml-cpp, which only Spike co-simulation needs.
    local objs="work-dpi/elfloader.o work-dpi/msim_helper.o work-dpi/remote_bitbang.o work-dpi/SimDTM.o work-dpi/SimJTAG.o"
    make -s $objs
    g++ -shared -fPIC -O2 -o work-dpi/ariane_dpi.so $objs "$REPO_ROOT/hw/engine/verif_stubs.cc" -I"$VCS_HOME/include" \
        -L"$RISCV/lib" -Wl,-rpath,"$RISCV/lib" -lfesvr -lriscv
    # OpenTitan AES + our DMA and wrappers (hw/engine), compiled into
    # the same VCS library before the CVA6 Makefile elaborates the harness.
    mkdir -p work-vcs
    python3 "$REPO_ROOT/hw/engine/gen_flist.py" "$OT_DIR" work-vcs/opentitan_aes.f >/dev/null
    (cd work-vcs && nice -n 10 vlogan -full64 -sverilog -nc -assert svaext -timescale=1ns/1ns \
        -f opentitan_aes.f "$REPO_ROOT"/hw/engine/aes_dma.sv "$REPO_ROOT"/hw/engine/aes_engine.sv \
        "$REPO_ROOT"/hw/engine/aes_engine_axi.sv \
        > "$LOGS/cva6_vcs_aes.log" 2>&1) || { grep -A4 'Error-\[' "$LOGS/cva6_vcs_aes.log" | head -20; exit 1; }
    # flist must be absolute: the Makefile runs vlogan from inside work-vcs/.
    # Defines: see hw/patches/cva6/0002-harness-aes-engine.patch.
    nice -n 10 make vcs_build flist="$CVA6_DIR/core/Flist.cva6" defines=MOCK_UART+AES_ENGINE+NO_TRACE+EXIT_ON_TOHOST \
        > "$LOGS/cva6_vcs_build.log" 2>&1 || { grep -A4 'Error-\[' "$LOGS/cva6_vcs_build.log" | head -20; exit 1; }
    echo ">> built $CVA6_DIR/work-vcs/simv (log: logs/cva6_vcs_build.log)"
}

run() {
    local elf; elf=$(readlink -f "$1")
    local name=${2:-$(basename "$(dirname "$elf")")_$(basename "$elf" .elf)}
    cd "$CVA6_DIR/work-vcs"
    # +elf_file: the test bench preloads the memory at once.
    # +debug_disable: keep the simulated debugger away from the core. It would
    #   halt the core now and then to poll tohost, and mcycle stops while halted,
    #   so anything timed against hardware outside the CPU would read too low.
    #   It would also load the program a second time, at 30 cycles per byte.
    # time_out: cycles before the tracer gives up (the default 2M is far too short).
    CVA6_ELF=$elf nice -n 10 ./simv +permissive +elf_file="$elf" +debug_disable +time_out=4000000000 \
        +permissive-off ++"$elf" -sv_lib ../work-dpi/ariane_dpi > "$LOGS/run_$name.log" 2>&1 || true
    grep -E '^(KAT|RESULT|CHECK|ALL|SOME)|SUCCESS|FAILED|Error' "$LOGS/run_$name.log" || true
    echo ">> log: logs/run_$name.log"
}

case "${1:-}" in
    build) build ;;
    run)   [ $# -ge 2 ] || { echo "usage: $0 run <prog.elf> [log name]" >&2; exit 1; }; run "$2" "${3:-}" ;;
    *)     echo "usage: $0 build | run <prog.elf> [log name]" >&2; exit 1 ;;
esac
