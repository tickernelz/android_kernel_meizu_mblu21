#!/usr/bin/env bash
set -euo pipefail

workspace=${1:?usage: apply_root.sh <workspace> <root-url> <root-sha> <patch|none> [config-lines] [root-ref]}
root_url=${2:?root repository url}
root_sha=${3:?root commit sha}
kernel_patch=${4:-none}
config_lines=${5:-}
root_ref=${6:-unknown}

common="$workspace/common"
root_dir="$workspace/root-src"

if [ ! -d "$common/drivers" ]; then
  echo "kernel common tree missing at $common" >&2
  exit 1
fi

rm -rf "$root_dir"
git clone --quiet --filter=blob:none --no-checkout "$root_url" "$root_dir"
git -C "$root_dir" fetch --quiet origin "$root_sha"
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

require_line() {
  if ! grep -qE "$2" "$1"; then
    echo "$1: expected a line matching $2 after pinning the driver version" >&2
    exit 1
  fi
}

pin_driver_version() {
  local dir=$1 file count tag sha8 base offset version
  file=$(grep -lE '^KSU_VERSION(_FALLBACK)?[[:space:]]*:=' "$dir/Kbuild" "$dir/Makefile" 2>/dev/null | head -1 || true)
  if [ -z "$file" ]; then
    echo "driver version: no KSU_VERSION assignment in Kbuild/Makefile, left to the driver build"
    return
  fi
  count=$(git -C "$root_dir" rev-list --count HEAD)
  tag=$(git -C "$root_dir" describe --tags --abbrev=0 HEAD)
  sha8=$(git -C "$root_dir" rev-parse --short=8 HEAD)
  if grep -qE '^VERSION_OFFSET[[:space:]]*:=' "$file"; then
    base=$(sed -nE 's/^VERSION_BASE[[:space:]]*:=[[:space:]]*([0-9]+).*/\1/p' "$file")
    offset=$(sed -nE 's/^VERSION_OFFSET[[:space:]]*:=[[:space:]]*([0-9]+).*/\1/p' "$file")
    version=$((base + count - offset))
    sed -i -E \
      -e 's/^KSU_GITHUB_VER[[:space:]]*:=.*/KSU_GITHUB_VER :=/' \
      -e 's/^GITHUB_COMMITS[[:space:]]*:=.*/GITHUB_COMMITS :=/' \
      -e "s/^KSU_VERSION[[:space:]]*:=.*/KSU_VERSION := $version/" \
      -e "s/^KSU_VERSION_FULL[[:space:]]*:=.*/KSU_VERSION_FULL := $tag-$sha8@$root_ref/" \
      "$file"
    require_line "$file" "^KSU_VERSION := $version$"
    require_line "$file" "^KSU_VERSION_FULL := $tag-$sha8@$root_ref$"
  elif grep -qE '^KSU_LOCAL_VERSION[[:space:]]*:=' "$file"; then
    sed -i -E \
      -e 's/^LOCAL_GIT_EXISTS[[:space:]]*:=.*/LOCAL_GIT_EXISTS := 1/' \
      -e "s/^KSU_LOCAL_VERSION[[:space:]]*:=.*/KSU_LOCAL_VERSION := $count/" \
      -e "s/^KSU_TAG_NAME[[:space:]]*:=.*/KSU_TAG_NAME := $tag/" \
      -e "s/^KSU_COMMIT_SHA[[:space:]]*:=[[:space:]]*\\$\\(shell.*/KSU_COMMIT_SHA := $sha8/" \
      -e 's/^ifneq \(\$\(shell cd \$\(KSU_SRC\); \$\(GIT_BIN\) diff-index.*/ifneq (0,0)/' \
      -e "s/^KSU_BRANCH_NAME[[:space:]]*:=.*/KSU_BRANCH_NAME := $root_ref/" \
      "$file"
    require_line "$file" '^LOCAL_GIT_EXISTS := 1$'
    require_line "$file" "^KSU_LOCAL_VERSION := $count$"
    require_line "$file" "^KSU_COMMIT_SHA := $sha8$"
    require_line "$file" '^ifneq \(0,0\)$'
  elif grep -qE '^KSU_VERSION_FALLBACK[[:space:]]*:=' "$file"; then
    base=$(sed -nE 's/.*expr[[:space:]]+([0-9]+)[[:space:]]*\+[[:space:]]*\$\(KSU_GIT_VERSION\).*/\1/p' "$file" | head -1)
    if [ -z "$base" ]; then
      echo "$file: no 'expr <base> + \$(KSU_GIT_VERSION)' version formula" >&2
      exit 1
    fi
    version=$((base + count))
    sed -i -E \
      -e 's/^GIT_ROOT[[:space:]]*:=.*/GIT_ROOT :=/' \
      -e "s/^KSU_VERSION_FALLBACK[[:space:]]*:=.*/KSU_VERSION_FALLBACK := $version/" \
      -e "s/^KSU_VERSION_TAG_FALLBACK[[:space:]]*:=.*/KSU_VERSION_TAG_FALLBACK := $tag/" \
      "$file"
    require_line "$file" '^GIT_ROOT :=$'
    require_line "$file" "^KSU_VERSION_FALLBACK := $version$"
    require_line "$file" "^KSU_VERSION_TAG_FALLBACK := $tag$"
  else
    echo "$file: unknown KSU_VERSION layout" >&2
    exit 1
  fi
  echo "driver version pinned in ${file#"$common/"}: commit count $count, tag $tag, $sha8@$root_ref"
  grep -nE '^(KSU_VERSION|KSU_VERSION_FULL|KSU_LOCAL_VERSION|KSU_TAG_NAME|KSU_COMMIT_SHA|KSU_BRANCH_NAME)[[:space:]]*:=' "$file"
}
pin_driver_version "$common/drivers/kernelsu"

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
grep -nE '^CONFIG_KSU|^CONFIG_KPM|^CONFIG_KPROBES' "$defconfig"
