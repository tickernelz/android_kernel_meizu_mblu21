#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: make_boot.sh <kernel-image> <output-image> <repo-root> [partition-size]}
output=${2:?output image path}
repo_root=${3:?repository root}
partition_size=${4:-67108864}
pagesize=4096

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
signed="$workdir/boot.img"

python3 "$repo_root/scripts/bootimg.py" pack --kernel "$image" --output "$signed" --pagesize "$pagesize" --header-version 4

python3 "$repo_root/tools/avbtool.py" add_hash_footer \
  --image "$signed" \
  --partition_size "$partition_size" \
  --partition_name boot \
  --algorithm SHA256_RSA4096 \
  --key "$repo_root/keys/testkey_rsa4096.pem" \
  --prop "com.android.build.boot.os_version:13" \
  --prop "com.android.build.boot.fingerprint:meizu/meizu_mblu/MEIZU_mblu:13/T00624/1745906188:user/release-keys" \
  --prop "com.android.build.boot.security_patch:2024-12-05"

python3 "$repo_root/tools/avbtool.py" verify_image --image "$signed"

size=$(stat -c %s "$signed")
if [ "$size" -gt "$partition_size" ]; then
  echo "boot.img is $size bytes, partition allows $partition_size" >&2
  exit 1
fi
mv "$signed" "$output"
python3 "$repo_root/scripts/bootimg.py" info "$output"
