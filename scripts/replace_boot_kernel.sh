#!/usr/bin/env bash
set -euo pipefail

usage="usage: replace_boot_kernel.sh <stock-boot.img> <kernel-image> <avb-key.pem> <output.img>"
stock=${1:?$usage}
kernel=${2:?$usage}
key=${3:?$usage}
output=${4:?$usage}
repo_root=$(cd "$(dirname "$0")/.." && pwd)
avbtool="$repo_root/tools/avbtool.py"
rollback_index_location=${ROLLBACK_INDEX_LOCATION:-1}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

python3 "$avbtool" info_image --image "$stock" > "$workdir/stock.info"
partition_size=$(stat -c %s "$stock")
salt=$(awk '/Salt:/{print $2; exit}' "$workdir/stock.info")
test -n "$salt"
props=()
while IFS= read -r line; do
  props+=(--prop "$line")
done < <(sed -n 's/^ *Prop: \(.*\) -> '"'"'\(.*\)'"'"'$/\1:\2/p' "$workdir/stock.info")
if [ "${#props[@]}" -eq 0 ]; then
  echo "no AVB properties found in $stock" >&2
  exit 1
fi

python3 - "$stock" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read(4096)
if b[:8] != b"ANDROID!":
    raise SystemExit("stock image has no ANDROID! magic")
ramdisk, os_version, header_size = struct.unpack_from("<III", b, 12)
header_version = struct.unpack_from("<I", b, 40)[0]
cmdline = b[44:44 + 1536].rstrip(b"\0")
signature_size = struct.unpack_from("<I", b, 1580)[0] if header_version == 4 else 0
if (header_version, ramdisk, os_version, cmdline, signature_size) != (4, 0, 0, b"", 0):
    raise SystemExit(f"unexpected stock header: v{header_version} ramdisk={ramdisk} os_version={os_version} cmdline={cmdline!r} signature={signature_size}")
PY

python3 "$repo_root/scripts/bootimg.py" pack --kernel "$kernel" --output "$workdir/boot.img" --pagesize 4096 --header-version 4
python3 "$avbtool" add_hash_footer \
  --image "$workdir/boot.img" \
  --partition_size "$partition_size" \
  --partition_name boot \
  --algorithm SHA256_RSA2048 \
  --key "$key" \
  --salt "$salt" \
  --rollback_index_location "$rollback_index_location" \
  "${props[@]}"
python3 "$avbtool" verify_image --image "$workdir/boot.img" --key "$key"
mv "$workdir/boot.img" "$output"
python3 "$repo_root/scripts/bootimg.py" info "$output"
