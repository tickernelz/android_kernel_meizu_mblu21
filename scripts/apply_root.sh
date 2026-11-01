#!/usr/bin/env bash
set -euo pipefail

workspace=${1:?usage: apply_root.sh <workspace> <root-url> <root-sha> <patch|none> [config-lines]}
root_url=${2:?root repository url}
root_sha=${3:?root commit sha}
kernel_patch=${4:-none}
config_lines=${5:-}

common="$workspace/common"
root_dir="$workspace/root-src"

if [ ! -d "$common/drivers" ]; then
  echo "kernel common tree missing at $common" >&2
  exit 1
fi

rm -rf "$root_dir"
git clone --quiet --filter=blob:none --no-checkout "$root_url" "$root_dir"
git -C "$root_dir" fetch --depth=1 --quiet origin "$root_sha"
git -C "$root_dir" -c advice.detachedHead=false checkout --quiet "$root_sha"
actual=$(git -C "$root_dir" rev-parse HEAD)
if [ "$actual" != "$root_sha" ]; then
  echo "root checkout is at $actual, expected $root_sha" >&2
  exit 1
fi

if [ -e "$common/drivers/kernelsu" ]; then
  echo "drivers/kernelsu already exists, refusing to overwrite" >&2
  exit 1
fi
cp -rL "$root_dir/kernel" "$common/drivers/kernelsu"
rm -rf "$common/drivers/kernelsu/.git"
leftover=$(find "$common/drivers/kernelsu" -type l)
if [ -n "$leftover" ]; then
  echo "symlinks left in drivers/kernelsu: $leftover" >&2
  exit 1
fi

if ! grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$common/drivers/Makefile"; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$common/drivers/Makefile"
fi
if ! grep -q 'drivers/kernelsu/Kconfig' "$common/drivers/Kconfig"; then
  sed -i '0,/^endmenu/s//source "drivers\/kernelsu\/Kconfig"\n\nendmenu/' "$common/drivers/Kconfig"
fi

if [ "$kernel_patch" != none ]; then
  android_patch=$(realpath "$kernel_patch")
  git -C "$common" apply --check "$android_patch"
  git -C "$common" apply "$android_patch"
  echo "applied $(basename "$android_patch")"
fi

defconfig="$common/arch/arm64/configs/gki_defconfig"
sed -i 's/^POST_DEFCONFIG_CMDS="check_defconfig"$/POST_DEFCONFIG_CMDS=""/' "$common/build.config.gki"
if grep -q 'check_defconfig' "$common/build.config.gki"; then
  echo "check_defconfig still referenced in build.config.gki" >&2
  exit 1
fi
while IFS= read -r line; do
  line=${line%%\#*}
  line=$(printf '%s' "$line" | tr -d '[:space:]')
  if [ -z "$line" ]; then
    continue
  fi
  if ! grep -qxF "$line" "$defconfig"; then
    printf '%s\n' "$line" >> "$defconfig"
  fi
done <<< "$config_lines"

echo "--- root integration ---"
grep -n 'kernelsu' "$common/drivers/Makefile" "$common/drivers/Kconfig"
grep -nE '^CONFIG_KSU|^CONFIG_KPROBES' "$defconfig"
