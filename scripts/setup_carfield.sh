#!/usr/bin/env bash
# Fetch Carfield at the commit pinned in deps/carfield.commit, then let Bender
# download its hardware dependencies. Safe to re-run.
#
#   scripts/setup_carfield.sh            clone/check + bender checkout
#   scripts/setup_carfield.sh --hw-init  also run `make car-hw-init` (generates RTL)
#
# It never runs `car-sim-init`: that step downloads simulation models with
# non-free licence terms and must be accepted by hand.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CAR_URL=https://github.com/pulp-platform/carfield.git
CAR_DIR=$REPO_ROOT/third_party/carfield
CAR_COMMIT=$(tr -d '[:space:]' < "$REPO_ROOT/deps/carfield.commit")
BENDER=${BENDER:-bender}


command -v "$BENDER" >/dev/null || { echo "bender not found; source env/setup.sh first" >&2; exit 1; }

# Git settings for the clones Bender makes (environment only, not ~/.gitconfig):
# - skip Cheshire's cva6-sdk submodule: it is the Linux SDK (buildroot, u-boot, ...),
#   several GB we don't need for bare-metal work;
# - use https:// for git:// URLs: the lab firewall blocks git's own port (9418).
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=submodule.sw/deps/cva6-sdk.update GIT_CONFIG_VALUE_0=none
export GIT_CONFIG_KEY_1=url.https://.insteadOf GIT_CONFIG_VALUE_1=git://
export BENDER_NO_PROGRESS=true

# 1. Clone, or check an existing clone.
if [ ! -d "$CAR_DIR/.git" ]; then
    echo ">> Cloning Carfield at $CAR_COMMIT"
    mkdir -p "$CAR_DIR"
    git -C "$CAR_DIR" init -q
    git -C "$CAR_DIR" remote add origin "$CAR_URL"
    git -C "$CAR_DIR" fetch -q --depth 1 origin "$CAR_COMMIT"
    git -C "$CAR_DIR" -c advice.detachedHead=false checkout -q FETCH_HEAD
else
    if [ -n "$(git -C "$CAR_DIR" status --porcelain --untracked-files=no)" ]; then
        echo "!! $CAR_DIR has local changes; not touching it." >&2
        echo "   Save them as a patch in hw/patches/ first." >&2
        exit 1
    fi
    if [ "$(git -C "$CAR_DIR" rev-parse HEAD)" != "$CAR_COMMIT" ]; then
        echo ">> Moving Carfield to $CAR_COMMIT"
        git -C "$CAR_DIR" fetch -q --depth 1 origin "$CAR_COMMIT"
        git -C "$CAR_DIR" -c advice.detachedHead=false checkout -q FETCH_HEAD
    else
        echo ">> Carfield already at $CAR_COMMIT"
    fi
fi

# 2. Download hardware IPs listed in Bender.lock (CVA6, clusters, OpenTitan, ...).
#    Same as `make car-checkout`.
echo ">> bender checkout"
(cd "$CAR_DIR" && nice -n 10 "$BENDER" checkout)

# 3. Optional: generate hardware (Cheshire config, Spatz, boot ROM, ...).
if [ "${1:-}" = "--hw-init" ]; then
    # Carfield's own Python venv. Its reggen scripts import pkg_resources,
    # which setuptools 81+ no longer ships, so pin an older setuptools.
    echo ">> Carfield venv (setuptools<81)"
    (cd "$CAR_DIR" && make venv >/dev/null && .venv/bin/pip install -q 'setuptools<81')
    # Run serially: with -j, Spatz's Makefile builds riscv-opcodes before cloning it.
    # GCC_INSTALL_DIR: Spatz's boot ROM normally uses Spatz's own GCC (built from
    # source); the lab's xPack GCC, linked as ~/tools/bin/riscv32-unknown-elf-*, works.
    echo ">> make car-hw-init"
    (cd "$CAR_DIR" && nice -n 10 make -j1 car-hw-init BENDER="$BENDER" GCC_INSTALL_DIR="$HOME/tools")
fi

echo ">> Done. Not run: car-sim-init (non-free simulation models; ask first)."
