Root for the unofficial **PixelOS 17** ROM on the Meizu mBlu 21 ([tickernelz/pixelos_build_mblu21](https://github.com/tickernelz/pixelos_build_mblu21), build `PixelOS_mblu21-17.0-20261105-1507`): SukiSU-Ultra `v4.3.0-r2` built from source and loaded as an LKM from `init_boot`. **Tested on hardware** on 2026-11-05 (results below). The stock-ROM images in `mblu21-root-20261102` are unchanged and remain the ones for the stock Meizu firmware.

## Source

| Component | Source | Pin |
|---|---|---|
| `kernelsu.ko`, `ksud`, `ksuinit` | [SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra/tree/v4.3.0-r2) | tag `v4.3.0-r2`, commit `645ef9860b9b7f900bb5d1b27e224f2c311d39c0`, version code 41150 |
| SUSFS guard | KernelSU-Next SUSFS guard, unchanged from `mblu21-susfs-lkm-20261102` | `susfs_guard_lkm.ko` `024aa0de…`, SUSFS `v2.3.0`, GKI |
| `init_boot` input | `IMAGES/init_boot.img` of PixelOS build 1507 (built from source: generic ramdisk only) | `738c81512a8d1bd2…` |
| Manager | upstream release asset, not re-signed | `SukiSU_v4.3.0-r2_41150-release.apk` `6fe64e7b…` |

Between `v4.3.0` (used before) and `v4.3.0-r2` only 17 files under `kernel/` changed; `userspace/ksud` and `uapi/` are identical, so the SUSFS ABI `ksud` speaks is the same. `v4.3.0-r1` to `v4.3.0-r2` changed only `manager/`. The 20 `ksu_*` symbols the guard resolves by name exist in both `v4.3.0` and `v4.3.0-r2` (the one `ksu_*` symbol removed in r2, `ksu_show_allow_list`, is not used by the guard), so the guard was not rebuilt. The newest upstream `tiann/KernelSU` kernel commit (`28db74f6`, #3964) is already in r2 as `85d05cf2`.

## Build

`build-sukisu.sh` builds `kernelsu.ko` in the same container the upstream CI uses (`ghcr.io/ylarod/ddk-min:android13-5.15-20260828`, `CONFIG_KSU=m CONFIG_KPM=y`, network off), then `ksuinit` and `ksud` with NDK r29 using the upstream workflow flags, with that `kernelsu.ko` and `ksuinit` embedded in `ksud`.

- `lkm-aarch64-android13-5.15_kernelsu-v4.3.0-r2.ko` is **byte-identical** to the upstream release asset `lkm-aarch64-android13-5.15_kernelsu.ko` (`f0d3f0a3…`).
- `ksud` and `ksuinit` differ in bytes from the upstream assets (`dec34535…`, `c7034b99…`); same source, different host toolchain. `ksud` bytes also varied between two local runs of the same source; `kernelsu.ko` and `ksuinit` did not.
- `build-sukisu-v4.3.0-r2.log` is the log of the run that produced these binaries. That run also tried a host (x86_64) `ksud` build, which does not compile at r2 (`error: could not compile ksud ... 18 previous errors`) after the Android binary was already built; that step was removed from the attached script.

`patch-init-boot.sh <stock init_boot.img> <out.img>` runs the Android `ksud boot-patch` on the host under `qemu-aarch64-static` with bionic from the PixelOS build output. Result ramdisk: `init` = `ksuinit`, `kernelsu.ko` = `f0d3f0a3…`, `init.real` = the original `init`. A patched `init_boot` matches one ROM build only: repatch from each new build's `init_boot.img`.

## Install (from an already rooted PixelOS 1507)

```sh
sha256sum -c SHA256SUMS
adb install -r SukiSU_v4.3.0-r2_41150-release.apk
adb push init_boot-PixelOS_mblu21-17.0-20261105-1507-sukisu-v4.3.0-r2.img /data/local/tmp/ib.img
adb shell su -c 'dd if=/dev/block/by-name/init_boot$(getprop ro.boot.slot_suffix) of=/data/local/tmp/init_boot-backup.img'
adb shell su -c 'dd if=/data/local/tmp/ib.img of=/dev/block/by-name/init_boot$(getprop ro.boot.slot_suffix) conv=fsync'
adb reboot
```

Pull `/data/local/tmp/init_boot-backup.img` to the PC before rebooting; writing it back the same way undoes the change. From an unrooted phone, write the image with `spd_dump` as in [docs/ROOT.md](https://github.com/tickernelz/android_kernel_meizu_mblu21/blob/main/docs/ROOT.md) (partition `init_boot_a` or `init_boot_b`, the active slot). The SUSFS guard module installs as in `mblu21-susfs-lkm-20261102`.

## Tested on hardware (2026-11-05, slot `_b`, `ro.build.date.utc=1793890890`)

| Check | Result |
|---|---|
| `ksud -V` | `ksud 4.3.0-r2 (uapi: 6)` |
| `/proc/modules` | `kernelsu 561152 1 - Live 0x0000000000000000 (OE)` |
| Manager | `v4.3.0-r2 (41150-6)`, "Working", `LKM`, kernel full version `v4.3.0-r2-645ef986@release`, SuSFS `v2.3.0` |
| `ksud susfs implementation / version / variant / status` | `lkm` / `v2.3.0` / `GKI` / `true`; guard log `rc=0 present=yes` |
| `su -c id`, `/system/bin/su -c id` | `uid=0(root) … context=u:r:ksu:s0` |
| `getenforce` | `Enforcing` |
| Data | kept, `user_setup_complete=1` (no wipe) |
| Stability | 0 panic/Oops in `dmesg`, `logcat -b crash` empty |
| Kernel | stock Meizu boot image (`uname` `5.15.149-android13-8-00008-gbe074b05e5af-ab12096863`), no KernelSU built in |

Raw output: `verify-on-phone-20261105.txt`.

Not tested: the `spd_dump` write path with this image, a phone not already rooted, and the stock Meizu ROM with r2. Observed once and not explained: after the reboot into this image, USB came up as MTP only and adb stayed off for 14 minutes (`AdbService` read `adb_enabled=0` at boot) until USB debugging was switched on again in Developer options.

The kernel path (`boot-<variant>.img`) is not tried on this phone; see the README.
