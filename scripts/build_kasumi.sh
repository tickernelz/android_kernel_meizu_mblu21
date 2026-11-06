#!/usr/bin/env bash
set -euo pipefail
src=${1:?kasumi source directory}
out=${2:?output .ko path}
cd "$src"
git config --global --add safe.directory "$src"
version=$(( $(git rev-list --count HEAD) + 200 ))
make -j"$(nproc)" CC=clang CFLAGS_MODULE="-DKASUMI_VERSION=\\\"0.1.${version}\\\""
cp src/kasumi_lkm.ko "$out"
llvm-strip -d "$out"
