#!/usr/bin/env bash
# Build and run upstream CVA6 (third_party/cva6) in VCS.
#   scripts/cva6_sim.sh build            compile the test harness (simv)
#   scripts/cva6_sim.sh run <prog.elf>   run a bare-metal program, log in logs/
#   scripts/cva6_sim.sh saif <prog.elf> <scope> <out.saif>
#                                        run it and write switching activity of
#                                        one instance (for Joules)
# Source env/setup.sh first. Run scripts/setup_cva6.sh once before.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CVA6_DIR=$REPO_ROOT/third_party/cva6
OT_DIR=$(cd "$REPO_ROOT/third_party/carfield" && bender path opentitan)
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
    g++ -shared -fPIC -O2 -o work-dpi/ariane_dpi.so $objs "$REPO_ROOT/hw/cva6_sim/dpi/verif_stubs.cc" -I"$VCS_HOME/include" \
        -L"$RISCV/lib" -Wl,-rpath,"$RISCV/lib" -lfesvr -lriscv
    # OpenTitan AES (from Carfield's checkout) + our bus wrapper, compiled into
    # the same VCS library before the CVA6 Makefile elaborates the harness.
    mkdir -p work-vcs
    python3 "$REPO_ROOT/hw/rtl/aes_periph/gen_flist.py" "$OT_DIR" work-vcs/opentitan_aes.f >/dev/null
    (cd work-vcs && nice -n 10 vlogan -full64 -sverilog -nc -assert svaext -timescale=1ns/1ns \
        -f opentitan_aes.f "$REPO_ROOT/hw/rtl/aes_periph/aes_periph.sv" \
        > "$LOGS/cva6_vcs_aes.log" 2>&1) || { grep -A4 'Error-\[' "$LOGS/cva6_vcs_aes.log" | head -20; exit 1; }
    # flist must be absolute: the Makefile runs vlogan from inside work-vcs/.
    # Defines: see hw/patches/cva6/0002-harness-mock-uart-aes.patch.
    # DEBUG=1 (UCLI access) is needed to dump switching activity for power runs.
    nice -n 10 make vcs_build flist="$CVA6_DIR/core/Flist.cva6" defines=MOCK_UART+AES_PERIPH DEBUG=1 \
        > "$LOGS/cva6_vcs_build.log" 2>&1 || { grep -A4 'Error-\[' "$LOGS/cva6_vcs_build.log" | head -20; exit 1; }
    echo ">> built $CVA6_DIR/work-vcs/simv (log: logs/cva6_vcs_build.log)"
}

run() {
    local elf; elf=$(readlink -f "$1")
    local name; name=$(basename "$(dirname "$elf")")_$(basename "$elf" .elf)
    cd "$CVA6_DIR/work-vcs"
    # time_out: cycles before the tracer gives up (default 2M is too short for 64 KB).
    CVA6_ELF=$elf nice -n 10 ./simv +permissive +elf_file="$elf" +time_out=200000000 +permissive-off ++"$elf" \
        -sv_lib ../work-dpi/ariane_dpi > "$LOGS/cva6_run_$name.log" 2>&1 || true
    grep -E '^(KAT|RESULT|BUF|ALL|SOME)|SUCCESS|FAILED|Error' "$LOGS/cva6_run_$name.log" || true
    echo ">> log: logs/cva6_run_$name.log"
}

saif() {
    local elf; elf=$(readlink -f "$1")
    local scope=$2 out; out=$(readlink -f "$3")
    local do_file=$CVA6_DIR/work-vcs/saif_$(basename "$out" .saif).do   # one per run: runs may be parallel
    # Stop when the program writes tohost (exit_o[0]), before the test bench
    # calls \$finish, so the report can still be written.
    cat > "$do_file" <<UCLI
stop -condition {ariane_tb.exit_o[0] == 1'b1}
power -gate_level rtl_on sv
power $scope
power -enable
run
power -disable
power -report $out 1e-09 $scope
quit
UCLI
    cd "$CVA6_DIR/work-vcs"
    CVA6_ELF=$elf nice -n 10 ./simv +permissive -lca -ucli -do "$do_file" +elf_file="$elf" \
        +time_out=200000000 +permissive-off ++"$elf" -sv_lib ../work-dpi/ariane_dpi \
        > "$LOGS/cva6_saif_$(basename "$out" .saif).log" 2>&1 || true
    grep -E '^ONLY|SUCCESS|FAILED|Error' "$LOGS/cva6_saif_$(basename "$out" .saif).log" || true
    ls -la "$out"
}

case "${1:-}" in
    build) build ;;
    saif)  [ $# -eq 4 ] || { echo "usage: $0 saif <prog.elf> <scope> <out.saif>" >&2; exit 1; }; shift; saif "$@" ;;
    run)   [ $# -eq 2 ] || { echo "usage: $0 run <prog.elf>" >&2; exit 1; }; run "$2" ;;
    *)     echo "usage: $0 build | run <prog.elf> | saif <prog.elf> <scope> <out.saif>" >&2; exit 1 ;;
esac
