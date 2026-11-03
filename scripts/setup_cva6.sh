#!/usr/bin/env bash
# Fetch upstream CVA6 (has the Zkn AES unit, core/aes.sv) at the commit in
# deps/cva6.commit, with only the submodules the RTL simulation needs.
# Carfield's own CVA6 is from 2023 and has no Zkn, so we use this one standalone.
# Then apply our patches from hw/patches/cva6/. Safe to re-run.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CVA6_URL=https://github.com/openhwgroup/cva6.git
CVA6_DIR=$REPO_ROOT/third_party/cva6
CVA6_COMMIT=$(tr -d '[:space:]' < "$REPO_ROOT/deps/cva6.commit")
PATCH_DIR=$REPO_ROOT/hw/patches/cva6

# Not needed for RTL simulation: UVM verification suite, random test generator,
# ISA manual, FPGA Ethernet.
SKIP="verif/core-v-verif verif/sim/dv docs/riscv-isa/riscv-isa-manual corev_apu/fpga/src/ariane-ethernet"

# 1. Clone, or check an existing clone. A clone with no commit yet (an
#    interrupted first fetch) is resumed.
if [ ! -d "$CVA6_DIR/.git" ] || ! git -C "$CVA6_DIR" rev-parse -q --verify HEAD >/dev/null; then
    echo ">> Cloning CVA6 at $CVA6_COMMIT"
    mkdir -p "$CVA6_DIR"
    git -C "$CVA6_DIR" init -q
    git -C "$CVA6_DIR" remote get-url origin >/dev/null 2>&1 || git -C "$CVA6_DIR" remote add origin "$CVA6_URL"
    git -C "$CVA6_DIR" fetch -q --depth 1 origin "$CVA6_COMMIT"
    git -C "$CVA6_DIR" -c advice.detachedHead=false checkout -q FETCH_HEAD
elif [ "$(git -C "$CVA6_DIR" rev-parse HEAD)" != "$CVA6_COMMIT" ]; then
    echo "!! $CVA6_DIR is not at $CVA6_COMMIT; move or remove it by hand." >&2
    exit 1
else
    echo ">> CVA6 already at $CVA6_COMMIT"
fi

# 2. Submodules (shallow), except the ones in SKIP.
for p in $(git -C "$CVA6_DIR" config -f .gitmodules --get-regexp '\.path$' | awk '{print $2}'); do
    case " $SKIP " in *" $p "*) continue ;; esac
    git -C "$CVA6_DIR" submodule update -q --init --recursive --depth 1 --recommend-shallow "$p" \
        || git -C "$CVA6_DIR" submodule update -q --init --recursive "$p"   # pinned commit not on a branch tip
done

# 3. Our patches (each applied once; a reverse-check tells us if it is already in).
for p in "$PATCH_DIR"/*.patch; do
    [ -e "$p" ] || continue
    if git -C "$CVA6_DIR" apply --reverse --check "$p" 2>/dev/null; then
        echo ">> already applied: $(basename "$p")"
    else
        echo ">> applying: $(basename "$p")"
        git -C "$CVA6_DIR" apply "$p"
    fi
done

echo ">> Done."
