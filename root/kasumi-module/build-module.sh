#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "${1:-kasumi_lkm-module.zip}")
ko=${2:-$here/kasumi_lkm.ko}
if [ ! -f "$ko" ]; then
  echo "missing $ko: download kasumi_lkm.ko from the release page or build it with scripts/build_kasumi.sh" >&2
  exit 1
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
install -m 644 "$here/module.prop" "$tmp/module.prop"
install -m 755 "$here/post-fs-data.sh" "$tmp/post-fs-data.sh"
install -m 644 "$ko" "$tmp/kasumi_lkm.ko"
(
  cd "$tmp"
  zip -q -X "$out" module.prop post-fs-data.sh kasumi_lkm.ko
)
sha256sum "$out"
