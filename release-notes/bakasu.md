Status on the Meizu mBlu 21: **not tried on a phone.** Built from [BakaSU](https://github.com/Baka-SU/BakaSU) (formerly ReSukiSU, derived from KernelSU) tag `v4.2.0-rc3` at `239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb`. BakaSU publishes no `kernelsu.ko` or `ksud`, so both are built here from that tag.

| File | Use | Contents |
|---|---|---|
| `init_boot-PixelOS_mblu21-17.0-20261105-1807-bakasu-v4.2.0-rc3.img` | `init_boot` on PixelOS 17 build `20261105-1807` | the build's stock `init_boot` (`738c8151…`) patched by `ksud boot-patch --kmi android13-5.15`: `init` = BakaSU `ksuinit`, plus `kernelsu.ko` |
| `android13-5.15_kernelsu.ko` | LKM | built in `ghcr.io/ylarod/ddk-min` (`android13-5.15`) with `CONFIG_KSU=m CONFIG_KSU_MULTI_MANAGER_SUPPORT=y CONFIG_KSU_TRACEPOINT_HOOK=y`, as upstream `ddk-lkm.yml` |
| `ksud-aarch64-linux-android`, `ksuinit` | userspace | built from `userspace/ksud` and `userspace/ksuinit` of the same tag |
| `boot-bakasu.img` | `boot` | GKI `5.15.149` kernel with BakaSU built in (`CONFIG_KSU=y`, tracepoint hooks), stock header and AVB properties, public test-key signature |
| `ReSukiSU_v4.2.0-rc3_35171-arm64-v8a-release.apk` | manager | unmodified upstream release asset (SHA-256 `25657bc4…`); package `com.resukisu.resukisu`, versionCode 35171 (`aapt` output in `lkm-bakasu.log`) |
| `SHA256SUMS-bakasu` | | checksums of the files above |

The kernel in this build sets `CONFIG_TMPFS_XATTR=y` (not set in the stock kernel on the phone or in earlier builds here) and keeps `CONFIG_OVERLAY_FS=y`; the build fails when either line is missing from `.config` (`kernel.config` in the artifact). The `init_boot` check decompresses the ramdisk and requires the cpio entries `kernelsu.ko` and `init.real`; `lkm-bakasu.log` lists every entry.

No SUSFS: `patches/0001-susfs-android13-5.15.patch` calls `ksu_setup_preinit_file` and `ksu_preinit_handle_post_execveat`, which `v4.2.0-rc3` does not define, so it is not applied. No KPM: BakaSU has no KPM support. Whether the SUSFS guard module works with this driver is not measured.

`kernelsu.ko` was checked against the stock kernel's symbol table: 215 imports, none missing, vermagic accepted through modversions; 75 symbols are not exported, so it needs `ksuinit` to load (plain `insmod` fails). Its load time against the 2000 ms Unisoc hang monitor is not measured yet.

Pick one root driver: write the stock `init_boot` back before switching between drivers. Licenses: BakaSU repository GPL-3.0, its `kernel/` GPL-2.0-only; source at the commit above.
