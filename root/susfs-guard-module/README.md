# SUSFS guard module

KernelSU module that loads `susfs_guard_lkm.ko` at boot, so SUSFS works on a phone rooted through `init_boot` (the LKM path) without a rebuilt kernel.

| File | Purpose |
|---|---|
| `module.prop` | module identity: id `susfs_guard_lkm`, version `v2.3.0-gki` |
| `post-fs-data.sh`, `service.sh` | both call `/data/adb/ksud insmod /data/adb/modules/susfs_guard_lkm/susfs_guard_lkm.ko` and return early when `/sys/module/susfs_guard_lkm` already exists |
| `build-module.sh` | rebuilds the installable zip from the files above plus a `susfs_guard_lkm.ko` |

The module binary is not vendored here. It is the KernelSU-Next SUSFS guard for `android13-5.15`, published in the `mblu21-root-20261102` release:

| Artifact | sha256 |
|---|---|
| `susfs_guard_lkm.ko` | `024aa0de96b9e2d45c7f9a086189d72f95d51028fec6621b48e5f548cd39dc26` |
| `susfs_guard_lkm-module.zip` (as published) | `55740001f1133f067b324a316c779fe8907275d120dfc94cb9d8cef359ac9f66` |

Rebuilding produces a zip whose own sha256 differs, because zip stores file timestamps; every entry inside is byte-identical to the published zip (`module.prop` `61e9e9a5…`, `post-fs-data.sh` and `service.sh` `93419214…`, `susfs_guard_lkm.ko` `024aa0de…`). Compare entry hashes, not the container.

## Use

```sh
adb push susfs_guard_lkm-module.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/susfs_guard_lkm-module.zip'
adb reboot
adb shell su -c 'ksud susfs implementation'   # lkm
adb shell su -c 'cat /data/adb/ksu/log/susfs_guard.log'
```

The log must end with `rc=0 present=yes` for the boot that just happened.

## Rebuild

```sh
./build-module.sh susfs_guard_lkm-module.zip /path/to/susfs_guard_lkm.ko
```

Works on the stock `5.15.149` kernel of this phone. It loads even though the module's vermagic says `5.15.202`, because `ksud insmod` loads with kallsyms access and skips the module version check, and the guard resolves SukiSU's symbols by name rather than by CRC.
