#!/usr/bin/env bash
set -euo pipefail

workspace=${1:?usage: sync_sources.sh <workspace> <kernel-common-sha> [jobs]}
kernel_sha=${2:?kernel/common commit to pin}
jobs=${3:-8}
manifest_branch=common-android13-5.15-2024-07

mkdir -p "$workspace"
cd "$workspace"

if [ ! -d .repo ]; then
  curl -fsSL -o repo https://storage.googleapis.com/git-repo-downloads/repo
  echo "${REPO_LAUNCHER_SHA256:-05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a}  repo" | sha256sum -c -
  chmod +x repo
  ./repo init -u https://android.googlesource.com/kernel/manifest -b "$manifest_branch" --depth=1
fi

mkdir -p .repo/local_manifests
cat > .repo/local_manifests/000-kernel-pin.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remove-project name="kernel/common"/>
  <project path="common" name="kernel/common" revision="$kernel_sha"/>
</manifest>
XML

for attempt in 1 2 3; do
  if ./repo sync -c -j"$jobs" --no-tags --fail-fast --force-sync --retry-fetches=3; then
    break
  fi
  echo "repo sync attempt $attempt failed" >&2
  if [ "$attempt" = 3 ]; then
    exit 1
  fi
  sleep 20
done

actual=$(git -C common rev-parse HEAD)
if [ "$actual" != "$kernel_sha" ]; then
  echo "kernel/common is at $actual, expected $kernel_sha" >&2
  exit 1
fi
echo "sources synced, kernel/common at $kernel_sha"
