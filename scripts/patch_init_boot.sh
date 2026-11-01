#!/usr/bin/env bash
set -euo pipefail

variant=${1:?usage: patch_init_boot.sh <variant> <ksud> <kernelsu.ko> <stock-image> <out-dir> [ksuinit]}
ksud=${2:?ksud binary}
kernelsu=${3:?kernelsu lkm}
stock=${4:?stock init_boot image}
out=${5:?output directory}
ksuinit=${6:-}
kmi=android13-5.15

mkdir -p "$out"

echo "variant: $variant"
echo "ksud: $("$ksud" --version 2>&1 | head -1)"
echo "kernelsu module: $(basename "$kernelsu") sha256 $(sha256sum "$kernelsu" | cut -d' ' -f1)"
echo "stock image: $(basename "$stock") sha256 $(sha256sum "$stock" | cut -d' ' -f1)"

patch_with() {
  "$ksud" boot-patch -b "$stock" -m "$kernelsu" -o "$out" --kmi "$kmi" "$@"
}

if [ -n "$ksuinit" ]; then
  if patch_with -i "$ksuinit"; then
    echo "patched with bundled ksuinit"
  else
    echo "ksud rejected --init, retrying without it" >&2
    patch_with
  fi
else
  patch_with
fi

image=$(find "$out" -name '*.img' | head -1)
if [ -z "$image" ]; then
  echo "ksud produced no image" >&2
  exit 1
fi
echo "patched image: $image"
sha256sum "$image"
