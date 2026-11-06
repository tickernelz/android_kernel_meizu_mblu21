#!/usr/bin/env bash
set -euo pipefail

usage="usage: kernel_release.sh stamp <kernel-common-dir> <kernel-common-sha> <scm-count> <build-number> | check <kernel-image> <expected-release>"
pattern='^5\.15\.149-android13-8-[0-9]{5}-g[0-9a-f]{12}-ab[0-9]+$'

config_value() {
  local key=$1 common=$2 values
  values=$(sed -n "s/^$key=//p" "$common/build.config.constants" "$common/build.config.common" | sort -u)
  if [ -z "$values" ] || [ "$(printf '%s\n' "$values" | wc -l)" -ne 1 ]; then
    echo "expected one $key in build.config.constants/build.config.common, found: ${values:-none}" >&2
    exit 1
  fi
  printf '%s' "$values"
}

stamp() {
  local common=${1:?$usage} sha=${2:?$usage} count=${3:?$usage} build=${4:?$usage}
  local head branch kmi version suffix release
  head=$(git -C "$common" rev-parse HEAD)
  if [ "$head" != "$sha" ]; then
    echo "kernel/common is at $head, expected $sha" >&2
    exit 1
  fi
  branch=$(config_value BRANCH "$common")
  kmi=$(config_value KMI_GENERATION "$common")
  version=$(awk -F' = ' '$1=="VERSION"{v=$2} $1=="PATCHLEVEL"{p=$2} $1=="SUBLEVEL"{s=$2} END{print v"."p"."s}' "$common/Makefile")
  suffix="-${branch%%-*}-$kmi-$(printf '%05d' "$count")-g${sha:0:12}-ab$build"
  release="$version$suffix"
  if ! [[ $release =~ $pattern ]]; then
    echo "computed release $release (BRANCH=$branch KMI_GENERATION=$kmi) does not match $pattern" >&2
    exit 1
  fi
  cat > "$common/scripts/setlocalversion" <<EOF
#!/bin/sh
printf '%s\n' '$suffix'
EOF
  echo "$release"
}

check() {
  local image=${1:?$usage} expected=${2:?$usage} banner release
  banner=$(grep -a -o -m1 'Linux version 5[^(]*' "$image" || true)
  release=$(printf '%s' "$banner" | awk '{print $3}')
  echo "$(basename "$image"): $banner"
  if [[ $release == *maybe-dirty* ]]; then
    echo "kernel release $release still carries maybe-dirty" >&2
    exit 1
  fi
  if ! [[ $release =~ $pattern ]]; then
    echo "kernel release '$release' does not match $pattern" >&2
    exit 1
  fi
  if [ "$release" != "$expected" ]; then
    echo "kernel release $release, expected $expected" >&2
    exit 1
  fi
}

command=${1:?$usage}
shift
case "$command" in
  stamp) stamp "$@" ;;
  check) check "$@" ;;
  *) echo "$usage" >&2; exit 1 ;;
esac
