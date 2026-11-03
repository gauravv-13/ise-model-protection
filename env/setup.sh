#!/usr/bin/env bash
# Environment setup. Source this file: `source env/setup.sh`
#
# The lab's EDA tools (VCS, Genus, PrimeTime, xPack RISC-V GCC, ...) are already
# on PATH from /etc/profile.d/eda.sh, so there are no modules to load.
# This adds our user-local tools and project variables on top.

ISE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)
export ISE_ROOT

_ise_front() { case ":${PATH:-}:" in *":$1:"*) ;; *) PATH="$1${PATH:+:$PATH}" ;; esac; }
_ise_back()  { case ":${PATH:-}:" in *":$1:"*) ;; *) PATH="${PATH:+$PATH:}$1" ;; esac; }

# User-local tools: bender, dtc, spike (links in ~/tools/bin).
_ise_front "$HOME/tools/bin"
# Joules is installed and licensed but not on the lab PATH.
_ise_back /eda/tools/cadence/DDI251/JSTUDIO251/bin
export PATH
unset -f _ise_front _ise_back

# Bender, as Carfield's Makefiles expect it.
export BENDER=bender

# RISC-V toolchain: the lab's xPack GCC (rv64 and rv32, Zkne supported).
export RISCV_PREFIX=riscv-none-elf-
export RISCV_GCC_BIN=/eda/tools/opensource/xpack-riscv-none-elf-gcc-15.2.0-1/bin

# Carfield checkout (see scripts/setup_carfield.sh).
export CAR_ROOT="$ISE_ROOT/third_party/carfield"

# Shared machine: default to 4 parallel jobs.
export MAKEFLAGS="${MAKEFLAGS:--j4}"

# Project Python environment, if it has been created (python3 -m venv .venv).
if [ -f "$ISE_ROOT/.venv/bin/activate" ] && [ -z "${VIRTUAL_ENV:-}" ]; then
    . "$ISE_ROOT/.venv/bin/activate"
fi
