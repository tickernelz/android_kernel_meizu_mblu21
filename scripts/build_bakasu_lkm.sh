#!/usr/bin/env bash
set -euo pipefail

src=${1:?usage: build_bakasu_lkm.sh <bakasu-source> <output.ko>}
out=${2:?output .ko path}
git config --global --add safe.directory "$src"
cd "$src/kernel"
CONFIG_KSU=m CONFIG_KSU_MULTI_MANAGER_SUPPORT=y CONFIG_KSU_TRACEPOINT_HOOK=y CC=clang make
cp kernelsu.ko "$out"
llvm-strip -d "$out"
