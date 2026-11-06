#!/usr/bin/env bash
set -euo pipefail

usage="usage: patch_kpm.sh <kernel-image> <output-image>"
image=${1:?$usage}
output=${2:?$usage}
kp_tag=0.14.0
kp_url=https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/$kp_tag
kptools_sha256=a6b912ca964d35427d7fbcd87273abac604970e9746fa0613362be971f07259d
kpimg_sha256=ab020f31ca1c058603917e46d8a6691fbce0dd5cdc135a9cd8dc780e89472716

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

fetch() {
  local name=$1 sum=$2
  if [ -n "${KP_DIR:-}" ] && [ -f "$KP_DIR/$name" ]; then
    cp "$KP_DIR/$name" "$workdir/$name"
  else
    curl -fsSL --retry 3 -o "$workdir/$name" "$kp_url/$name"
  fi
  echo "$sum  $workdir/$name" | sha256sum -c - >/dev/null
}
fetch kptools-linux "$kptools_sha256"
fetch kpimg "$kpimg_sha256"
chmod +x "$workdir/kptools-linux"

"$workdir/kptools-linux" -l -i "$image" > "$workdir/input.txt"
if grep -qx 'patched=true' "$workdir/input.txt"; then
  echo "$image is already patched with KernelPatch; pass the unpatched kernel Image" >&2
  exit 1
fi

superkey=$(head -c 32 /dev/urandom | sha256sum | cut -c1-32)
"$workdir/kptools-linux" -p -i "$image" -k "$workdir/kpimg" --skey-fd 3 -o "$workdir/Image" 3<<<"$superkey" > "$workdir/patch.log"
unset superkey

in_size=$(stat -c %s "$image")
out_size=$(stat -c %s "$workdir/Image")
kpimg_size=$(stat -c %s "$workdir/kpimg")
if [ "$out_size" -lt $((in_size + kpimg_size)) ]; then
  echo "patched image is $out_size bytes, expected at least $in_size + kpimg $kpimg_size: KernelPatch payload missing" >&2
  exit 1
fi
"$workdir/kptools-linux" -l -i "$workdir/Image" > "$workdir/list.txt"
if ! grep -qx 'patched=true' "$workdir/list.txt"; then
  echo "kptools does not report the output as patched" >&2
  exit 1
fi
mv "$workdir/Image" "$output"
echo "KernelPatch $kp_tag: $(grep -m1 '^version=' "$workdir/list.txt"), $in_size -> $out_size bytes"
