# Kasumi module

KernelSU module that loads `kasumi_lkm.ko` at boot on the SukiSU-Ultra LKM root, without SUSFS. Background and test plan: [docs/ROOT-MODULES.md](../../docs/ROOT-MODULES.md).

| File | Purpose |
|---|---|
| `module.prop` | module identity: id `kasumi_lkm`, version `v0.1.340` (Kasumi's own version number for commit `049d5e93`) |
| `post-fs-data.sh` | skips and logs when `susfs_guard_lkm`, `pathmask`, `procguard`, `nomount` or `hybridmount` is loaded; otherwise `/data/adb/ksud insmod /data/adb/modules/kasumi_lkm/kasumi_lkm.ko` |
| `build-module.sh` | builds the installable zip from the files above plus a `kasumi_lkm.ko` |

`ksud insmod` is needed rather than `insmod`: six symbols Kasumi uses are not exported by the stock kernel and are resolved from kallsyms.

## Rebuild

```sh
git clone https://github.com/Rouyashiki/Kasumi && git -C Kasumi checkout 049d5e93f0e25877b0125da31bdef7fdd07e5c01
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/Kasumi:/src" -v "$PWD/scripts:/scripts:ro" \
  ghcr.io/ylarod/ddk-min@sha256:9e68cd9fcab748584755d31ba88ef134efc938dbde17f258c2652315f6cd81cd \
  /scripts/build_kasumi.sh /src /src/kasumi_lkm.ko
sha256sum Kasumi/kasumi_lkm.ko   # cc20e3a908ba487688205efdc0b0cd862b08d003a7faf95437e7da7c384ed09f
root/kasumi-module/build-module.sh kasumi_lkm-module.zip Kasumi/kasumi_lkm.ko
```

The zip's own hash changes with file timestamps; compare the entries inside it.

## Check on the phone

```sh
adb shell su -c 'cat /data/adb/ksu/log/kasumi.log'   # last line: rc=0 present=yes
```
