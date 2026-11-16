#!/usr/bin/env bash
# Fetch the OpenTitan AES block (and the primitives it needs) into
# third_party/opentitan, at the commit in deps/opentitan.commit. This is the
# pulp-platform fork and revision that Carfield's security island uses.
# Sparse checkout: about 55 MB instead of the whole repository. Safe to re-run.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OT_URL=https://github.com/pulp-platform/opentitan.git
OT_DIR=$REPO_ROOT/third_party/opentitan
OT_COMMIT=$(tr -d '[:space:]' < "$REPO_ROOT/deps/opentitan.commit")

if [ -d "$OT_DIR/.git" ] && [ "$(git -C "$OT_DIR" rev-parse -q --verify HEAD 2>/dev/null)" = "$OT_COMMIT" ]; then
    echo ">> OpenTitan already at $OT_COMMIT"
    exit 0
fi

echo ">> Fetching OpenTitan AES sources at $OT_COMMIT"
mkdir -p "$OT_DIR"
git -C "$OT_DIR" init -q
git -C "$OT_DIR" remote get-url origin >/dev/null 2>&1 || git -C "$OT_DIR" remote add origin "$OT_URL"
git -C "$OT_DIR" sparse-checkout init --cone
git -C "$OT_DIR" sparse-checkout set \
    hw/ip/aes hw/ip/prim hw/ip/prim_generic hw/ip/tlul hw/ip/csrng hw/ip/edn hw/ip/entropy_src \
    hw/ip/flash_ctrl hw/ip/keymgr hw/ip/lc_ctrl hw/ip/otp_ctrl hw/ip/rv_dm \
    hw/top_earlgrey/ip hw/top_earlgrey/ip_autogen hw/top_earlgrey/rtl hw/vendor/lowrisc_ibex/dv
git -C "$OT_DIR" fetch -q --depth 1 --filter=blob:none origin "$OT_COMMIT"
git -C "$OT_DIR" -c advice.detachedHead=false checkout -q FETCH_HEAD
echo ">> Done."
