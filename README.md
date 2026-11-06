# Kernel and root for Meizu mBlu 21 (M416H)

Kernel sources and root images for the Meizu mBlu 21: a GKI `boot` image with a root driver built in, and an `init_boot` image that loads root as a loadable module. Two root implementations are supported, SukiSU-Ultra and KernelSU-Next.

**Start here: [docs/ROOT.md](docs/ROOT.md) — step-by-step root tutorial (unlock, write, manager, root hiding, back to stock).** What the bootloader actually enforces on this phone, and the measurements behind it, are in [docs/HARDWARE-2026-11-02.md](docs/HARDWARE-2026-11-02.md).

| | |
|---|---|
| SoC | Unisoc T606 (UMS9230), board `ums9230_6h10` |
| Stock kernel | GKI `5.15.149-android13-8-00008-gbe074b05e5af-ab12096863` (KMI `android13-5.15`) |
| Source base | `android.googlesource.com/kernel/common`, tag `android13-5.15-2024-07_r1`, commit `be074b05e5aff5eb16a848fb3aaab2f73d687cb6` |
| `boot` partition | 67,108,864 bytes, boot header v4, kernel only (stock kernel 47,172,096 bytes) |
| `init_boot` partition | 8,388,608 bytes, boot header v4, ramdisk 2,155,827 bytes in the stock image |
| `vendor_boot` | not touched by anything here; recovery and first-stage modules stay stock |

## Documentation

| Page | What it covers |
|---|---|
| [docs/ROOT.md](docs/ROOT.md) | **Root tutorial**: Linux and Windows prerequisites, bootloader unlock, download-mode writes, manager app, proving root, SUSFS setup, restore to stock, troubleshooting |
| [docs/HARDWARE-2026-11-02.md](docs/HARDWARE-2026-11-02.md) | Hardware session results: which partitions AVB verifies, what was flashed, root evidence, live partition hashes, known gaps |
| [docs/PLAY-INTEGRITY.md](docs/PLAY-INTEGRITY.md) | Play Integrity: the verdicts measured on the test phone and how they were checked |
| [docs/ROOT-MODULES.md](docs/ROOT-MODULES.md) | Optional root variants without SUSFS (YukiSU, Kasumi, YukiZygisk): how to pick one, why Kasumi and SUSFS exclude each other, pinned artifacts, the stock-kernel symbol check, test plan and recovery |
| [root/kasumi-module/](root/kasumi-module/) | Sources of the KernelSU module that loads `kasumi_lkm.ko` at boot, plus `build-module.sh` |
| [root/susfs-guard-module/](root/susfs-guard-module/) | Sources of the KernelSU module that loads the SUSFS guard at boot, plus `build-module.sh` to rebuild the zip |
| [Releases](https://github.com/tickernelz/android_kernel_meizu_mblu21/releases) | `mblu21-root-20261102` holds the tested images, the SUSFS guard module and the manager APKs; `mblu21-susfs-lkm-20261102` holds the SUSFS module alone. Stock images are in [android_stock_meizu_mblu21](https://github.com/tickernelz/android_stock_meizu_mblu21/releases) |

## Status

The **LKM path is tested on hardware**: both `init_boot` images boot and give root on a real mBlu 21, and the SUSFS guard module survives a reboot (details in [docs/HARDWARE-2026-11-02.md](docs/HARDWARE-2026-11-02.md)).

The **LKM path on the unofficial PixelOS 17 ROM** ([pixelos_build_mblu21](https://github.com/tickernelz/pixelos_build_mblu21), builds `20261105-1507` and `20261105-1807`, the latter shown as `20261105-1800` on the phone) **is tested on hardware** with SukiSU-Ultra `v4.3.0-r2` and KernelSU-Next `v3.4.2`, both built from their release tags: `ksud` reports its version, `kernelsu` loaded, SUSFS `v2.3.0`, `su` gives `u:r:ksu:s0`, SELinux Enforcing, data kept (releases `mblu21-pixelos-root-20261105` and `mblu21-pixelos-root-20261106`). That ROM ships the stock Meizu boot image, so its kernel has no KernelSU built in. These images have not been tried on the stock Meizu ROM.

The **KPM boot (`boot` = GKI kernel built here + KernelPatch, root still from the LKM `init_boot`) is tested on hardware** (2026-11-06, PixelOS 17 build `20261105-1807`): the kernel built from `be074b05` with the stock `gki_defconfig` (full LTO), patched by `scripts/patch_kpm.sh` and packed by `scripts/replace_boot_kernel.sh` (`c68132ad…`, signed RSA-2048 with our own key) boots in 48 s on two consecutive reboots, `uname -r` `5.15.149-maybe-dirty`, SELinux Enforcing, `su` gives `u:r:ksu:s0`, `ksud extension list` shows `[AVAILABLE] kpm`, `ksud kpm version` `3584 (19:40:23 Oct 26 2026)`, SUSFS `v2.3.0` active, and all 108 `vendor_dlkm` and 2 `system_dlkm` modules load (180 in `/proc/modules`, the same as the stock kernel). With the bootloader unlocked, a foreign signature on `boot` is logged and ignored ([docs/AVB-POLICY.md](docs/AVB-POLICY.md)).

The **kernel path with the driver built in is tested on hardware for SukiSU-Ultra only** (2026-11-06, PixelOS 17 build `20261105-1807`): `Image` from the `sukisu-ultra-20261106-untested` pre-release (`boot-sukisu-ultra` and `boot-sukisu-ultra-kpm`), re-signed with our own RSA-2048 key by `scripts/replace_boot_kernel.sh` against the stock `boot_a`, with the stock PixelOS `init_boot` and no LKM, boots in 45.4 s (`boot-sukisu-ultra`) and 48.0/49.0 s (`boot-sukisu-ultra-kpm`), SELinux Enforcing, `su` gives `u:r:ksu:s0`, `ksud susfs` `true`/`v2.3.0`/`GKI`/`builtin`, 179 modules with no `kernelsu` or `susfs_guard_lkm`, and `[AVAILABLE] kpm` on the KPM image. The CI assets carry the public test key; the phone ran the same kernel re-signed. `boot-kernelsu-next.img` and `boot-bakasu.img` are still unmeasured on hardware. The 2026-11-03 image from `feat/sukisu-kpm` (`61d6e77d…`) stopped at the logo because `patch_linux` 0.14.0 dropped the KernelPatch payload from it, not because of the signature or the built-in driver.

Three optional variants without SUSFS (`yukisu`, `kasumi`, `yukizygisk`), built by `root-modules.yml`, are **not tried on the phone yet**; the SUSFS variants stay the default. See [docs/ROOT-MODULES.md](docs/ROOT-MODULES.md).

## Two paths

| Path | What is flashed | Kernel changed | Root | SUSFS (root hiding) |
|---|---|---|---|---|
| LKM (**tested**) | `init_boot` | no | kernel module loaded by the patched ramdisk | SukiSU-Ultra: yes, via the guard module. KernelSU-Next: yes, same guard module |
| KPM boot (**tested**) | `boot` and the LKM `init_boot` | GKI kernel plus KernelPatch | LKM, as above | same guard module as the LKM path |
| Kernel (**tested** for SukiSU-Ultra; KernelSU-Next and BakaSU not tried) | `boot` | yes | driver built into the kernel | SukiSU-Ultra: yes, kernel-side SUSFS patch (`builtin`, no guard module). KernelSU-Next: no kernel patch; SUSFS comes from its `susfs_guard_lkm.ko`. BakaSU: none |

LKM path status per variant:

| Variant | LKM for `android13-5.15` | Patched `init_boot` |
|---|---|---|
| KernelSU-Next | `aarch64_android13-5.15_kernelsu.ko` from release `v3.4.2` | patched on the CI host with the official `ksud-x86_64-unknown-linux-musl` (`ksud boot-patch --kmi android13-5.15`) from the stock `init_boot_a.bin` |
| SukiSU-Ultra | `lkm-aarch64-android13-5.15_kernelsu.ko` from release `v4.3.0` | patched **on the phone** with the Android `ksud` that ships in `v4.3.0`; the result is attached to the `mblu21-root-20261102` release |
| SukiSU-Ultra on PixelOS 17 | `kernelsu.ko` built from `v4.3.0-r2` (`645ef986`), byte-identical to the release asset | patched on the host with `ksud` built from `v4.3.0-r2` (run under `qemu-aarch64`) from that ROM build's `init_boot.img`; one image per ROM build, attached to `mblu21-pixelos-root-20261105` |

Pick one path and one variant. Flashing two root drivers is not a supported combination.

Why the two implementations differ here:

- SukiSU-Ultra ships SUSFS support in its `builtin` branch (its Kconfig defines `KSU_SUSFS`), but the hiding itself needs the `susfs4ksu` kernel patch, so the kernel path is built with `patches/0001-susfs-android13-5.15.patch` applied.
- KernelSU-Next keeps its SUSFS implementation in a loadable module (`susfs_guard_lkm.ko`, built from `kernel/susfs/` in its tree), so its kernel carries only the root driver and needs no source patch. That module also attaches to SukiSU-Ultra's LKM, which is why one guard module serves both variants.

## Static validation

The phone's vendor modules (113 in `vendor_dlkm`, 139 in the `vendor_boot` first-stage ramdisk) were built against the stock kernel and carry a `__versions` section: the CRC of every symbol they import. A kernel whose symbol CRCs differ from the stock kernel loads those modules only by luck; a mismatch on the symbols they use is what turns a custom kernel into a bootloop.

`scripts/module_abi.py` reads `__versions` and the `__ksymtab_*`/`__crc_*` symbols out of every stock module, stores the result as derived text in `abi/` (no vendor binaries are redistributed), and compares it against the built kernel's `Module.symvers`:

| Module set | Modules | Imported symbols | Exported symbols |
|---|---|---|---|
| `vendor_boot` first-stage ramdisk | 139 | 7,031 | 493 |
| `vendor_dlkm` | 113 | 6,621 | 540 |
| `system_dlkm` | 2 | 151 | 10 |

- A symbol imported from another stock module is skipped: that binary does not change. Across all three sets, 927 such imports point at 805 module exports, and every one of them carries the same CRC on both sides.
- `--self-test` perturbs a fifth of the kernel symbols and drops a tenth, then asserts the checker reports exactly those failures. Without it, a checker that always prints zero would look identical to a good kernel.

Result of the first green build (run 41279553995, both variants identical):

| Module set | Imports checked against vmlinux | Imports between stock modules | CRC mismatches | Missing symbols |
|---|---|---|---|---|
| `vendor_boot` | 6,581 | 450 | 0 | 0 |
| `vendor_dlkm` | 6,154 | 467 | 0 | 0 |
| `system_dlkm` | 141 | 10 | 0 | 0 |

The self-test passed in all three sets. The kernel's GKI protected-symbol lists (`android/abi_gki_modules_protected`, `android/abi_gki_modules_exports`) are empty at this tag, so unsigned vendor modules are not blocked from any symbol.

Measured differences from the stock kernel, from the embedded `/proc/config.gz` of each image:

- Added: `CONFIG_KSU=y` and the root implementation's options (SukiSU-Ultra also the ten `CONFIG_KSU_SUSFS*` options).
- `CONFIG_LTO_CLANG_THIN` instead of `CONFIG_LTO_CLANG_FULL` (Kleaf `--config=fast`); symbol CRCs do not depend on it, which the gate above confirms.
- `CONFIG_LOCALVERSION_AUTO` and `CONFIG_MODULE_SCMVERSION` off: the release string is `5.15.149-maybe-dirty` instead of `5.15.149-android13-8-00008-gbe074b05e5af-ab12096863`. With `CONFIG_MODVERSIONS` the kernel ignores the release part of a module's vermagic and compares only the flags (`SMP preempt mod_unload modversions aarch64`), which match. Apps can read the different string from `uname`; SUSFS `SPOOF_UNAME` exists for that.
- Kernel size: SukiSU-Ultra 41,785,856 bytes, KernelSU-Next 41,781,760 bytes, stock 47,172,096 bytes; each `boot-<variant>.img` is padded to exactly the 67,108,864-byte partition.

CI fails the build on any mismatch or missing symbol, so `0 mismatches / 0 missing` in the job summary means the checker ran and found nothing, not that it was skipped.

What this does **not** prove: that the kernel boots, that the bootloader accepts the image, that SUSFS actually hides anything from a given app, or that the vendor modules work at runtime. Those are runtime facts and are unverified until the images run on hardware.

## Releases

Six kinds of release:

| Release | Contents |
|---|---|
| `mblu21-root-20261102` | **Tested on hardware.** `init_boot-sukisu-ultra-lkm.img` and `init_boot-kernelsu-next-lkm.img` (both boot, both give root), the SUSFS guard module (`susfs_guard_lkm.ko` plus `susfs_guard_lkm-module.zip`), both manager APKs (SukiSU-Ultra and KernelSU-Next), the patch logs, and `SHA256SUMS` |
| `mblu21-pixelos-root-20261105` | **Tested on hardware**, PixelOS 17 build `20261105-1507` (the image also fits `20261105-1807`, which has the same stock `init_boot`). `init_boot` patched with SukiSU-Ultra `v4.3.0-r2`, `ksud`/`kernelsu.ko`/`ksuinit` built from source, the SUSFS guard module (unchanged), the upstream r2 manager APK, the build log, `build-sukisu.sh` and `patch-init-boot.sh`, the on-phone check output, and `SHA256SUMS` |
| `mblu21-pixelos-root-20261106` | **Tested on hardware**, PixelOS 17 build `20261105-1807` (`20261105-1800` on the phone; and every build with the same stock `init_boot`). Two `init_boot` images, SukiSU-Ultra `v4.3.0-r2` and KernelSU-Next `v3.4.2`, with `ksud`/`kernelsu.ko`/`ksuinit` built from the release tags (both `kernelsu.ko` and the KernelSU-Next SUSFS guard byte-identical to upstream), the SUSFS guard module, both upstream manager APKs, `build-sukisu.sh`, `build-ksunext.sh`, `patch-init-boot.sh`, both build logs, the on-phone check output, and `SHA256SUMS` |
| `mblu21-susfs-lkm-20261102` | **Tested on hardware.** The SUSFS guard KernelSU module alone (`susfs_guard_lkm.zip`, same bytes as `susfs_guard_lkm-module.zip` above) for SukiSU-Ultra in LKM mode, plus `SHA256SUMS` |
| `<variant>-<date>` (CI pre-release) | One per root variant, built by `build.yml`: `boot-<variant>.img` (on the phone only the SukiSU-Ultra kernel was tried, re-signed with our key; see [Status](#status)), `init_boot-<variant>-lkm.img`, the ABI reports, `config-report.txt`, `lkm-<variant>.log` |
| `yukisu|kasumi|yukizygisk-<tag>-untested` (CI pre-release) | Built by `root-modules.yml`, **not tried on the phone**: the pinned upstream modules (YukiSU LKM, APK and `ksud` with signatures; `kasumi_lkm.ko` built from source plus its loader zip; the YukiZygisk zip), `module-abi-<variant>.txt`, `SHA256SUMS-<variant>`. See [docs/ROOT-MODULES.md](docs/ROOT-MODULES.md) |

## Install

**The full procedure, including bootloader unlock and the download-mode writes this phone requires, is [docs/ROOT.md](docs/ROOT.md).** This section is the short form.

Prerequisites:

- Unlocked bootloader. `vbmeta` on this phone must stay Meizu-signed even when unlocked, so nothing here replaces it. The chained partitions `boot`, `init_boot` and `vendor_boot` are verified, but while unlocked a mismatch is logged and ignored ([docs/AVB-POLICY.md](docs/AVB-POLICY.md)).
- A full stock backup. `boot_a.bin` and `init_boot_a.bin` from the phone are the only reliable way back. The untouched U01005 images are also in the stock firmware release [mblu21-stock-U01005-20261031](https://github.com/tickernelz/android_stock_meizu_mblu21/releases/tag/mblu21-stock-U01005-20261031) as `boot_a.bin` and `init_boot_a.bin`.
- `adb`, and `spd_dump` from [TomKing062/CVE-2022-38694_unlock_bootloader](https://github.com/TomKing062/CVE-2022-38694_unlock_bootloader/releases) for the writes. `fastboot flash` does not work on this unit.

Verify a download first:

```sh
sha256sum -c SHA256SUMS
```

### Path B (recommended) - `init_boot` with the root module

`init_boot` carries only the generic ramdisk; the stock kernel stays in place. This is the tested path.

```sh
cd ~/tools/linux     # spd_dump + fdl1-dl.bin + fdl2-dl.bin live here
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec w init_boot_a ~/mblu21-root/init_boot-sukisu-ultra-lkm.img reset
```

Then install the matching manager and open it once:

| Variant | Manager |
|---|---|
| SukiSU-Ultra | `SukiSU_v4.3.0_41100-release.apk` - attached to `mblu21-root-20261102`, or from `SukiSU-Ultra/SukiSU-Ultra` release `v4.3.0` |
| KernelSU-Next | `KernelSU_Next_v3.4.2_33355-release.apk` - attached to `mblu21-root-20261102`, or from `KernelSU-Next/KernelSU-Next` release `v3.4.2` |

### KPM boot - KernelPatch in `boot`, root from the LKM `init_boot`

Install Path B first; the KPM loader in `kernelsu.ko` talks to KernelPatch through `__arm64_sys_truncate`, so both pieces are needed. Build the kernel and pack it (see [Build](#build)), keep a copy of `boot_a`, then write it as root:

```sh
adb shell su -c 'dd if=/dev/block/by-name/boot_a of=/data/local/tmp/boot_a.stock.img'
adb pull /data/local/tmp/boot_a.stock.img
adb push boot-kpm.img /data/local/tmp/
adb shell su -c 'dd if=/data/local/tmp/boot-kpm.img of=/dev/block/by-name/boot_a bs=1M conv=fsync'
adb reboot
adb shell su -c 'ksud extension list; ksud kpm version'
```

`[AVAILABLE] kpm` and a version line mean the loader answers. To undo, write `boot_a.stock.img` back the same way (or `boot_b`, which stays stock).

### Path A - kernel with the driver built in (SukiSU-Ultra tested on the phone, other variants not tried)

```sh
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec w boot_a boot-sukisu-ultra.img reset
```

The bootloader accepts a foreign signature on `boot` while unlocked ([docs/AVB-POLICY.md](docs/AVB-POLICY.md)); whether this kernel boots is not measured.

### Root hiding (SUSFS)

```sh
adb push susfs_guard_lkm-module.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/susfs_guard_lkm-module.zip'
adb reboot
```

Works on either LKM variant (on KernelSU-Next, check with `ksud susfs version`; it has no `susfs status`). Steps and verification commands are in [docs/ROOT.md](docs/ROOT.md#6-root-hiding-for-banking-apps-susfs).

## Back to stock

```sh
cd ~/tools/linux
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec w init_boot_a init_boot_a.bin reset
```

`init_boot_a.bin` is your backup, or the same file from the stock firmware release [mblu21-stock-U01005-20261031](https://github.com/tickernelz/android_stock_meizu_mblu21/releases/tag/mblu21-stock-U01005-20261031) (`d07159a1…`). Flashing only the partition you changed is enough. If you also replaced `boot_a`, write `boot_a.bin` (`3a78e139…`) back the same way. Userdata is untouched by both operations.

## What is not touched

- `vendor_boot`: recovery and the first-stage ramdisk stay as shipped. Recovery images live in [android_device_meizu_mblu21-recovery](https://github.com/tickernelz/android_device_meizu_mblu21-recovery), and a foreign `vendor_boot` loads while the bootloader is unlocked ([docs/HARDWARE-2026-11-02.md](docs/HARDWARE-2026-11-02.md), [docs/AVB-POLICY.md](docs/AVB-POLICY.md)).
- `vendor_dlkm`, `system_dlkm`, `vendor`, `odm`, `dtbo`, `vbmeta*`: untouched. Nothing here needs a disabled verification chain beyond the unlocked bootloader.
- The phone itself: nothing in this repository writes to a device; images are built from sources and files in this repository.

## Provenance

| Component | Source | Pin |
|---|---|---|
| Kernel | `android.googlesource.com/kernel/common` | tag `android13-5.15-2024-07_r1` (`be074b05e5af`) via manifest branch `common-android13-5.15-2024-07` |
| SukiSU-Ultra driver (kernel path) | `github.com/SukiSU-Ultra/SukiSU-Ultra` | `builtin` at `1cfa57340590971cba7521ed536da8ebbedc5f0a`, with `CONFIG_KSU_SUSFS=y` and `CONFIG_KPM=y`. The release tag `v4.3.0-r2` (`645ef986`) cannot be built in: its Kconfig has no `KSU_SUSFS`, and it defines none of the hooks the SUSFS patch calls (`ksu_handle_execveat`, `ksu_handle_stat`, `ksu_handle_faccessat`, `ksu_handle_sys_reboot`, `ksu_setup_preinit_file`) |
| BakaSU driver (kernel path and LKM) | `github.com/Baka-SU/BakaSU` (formerly ReSukiSU; repository GPL-3.0, `kernel/` GPL-2.0-only) | tag `v4.2.0-rc3` at `239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb`, tracepoint hooks, no SUSFS: the SUSFS patch calls `ksu_setup_preinit_file` and `ksu_preinit_handle_post_execveat`, which this tag does not define |
| KernelSU-Next driver (kernel path) | `github.com/KernelSU-Next/KernelSU-Next` | `dev` at `cefb048b069b7439fb4020d043de2d338dbc00fa` |
| Kernel release string | `scripts/kernel_release.sh` | `5.15.149-android13-8-00008-gbe074b05e5af-ab<GITHUB_RUN_NUMBER>`, the stock format; `android13` and `8` come from `BRANCH` and `KMI_GENERATION` in the tree, `00008` is written out because the sources are a shallow clone |
| SUSFS patch | `gitlab.com/simonpunk/susfs4ksu` | `gki-android13-5.15` at `3f3073a9f76247af765bfeba7908f4d3c580f2bc` |
| LKM images | flavour release assets plus a host build of `ksud` | SukiSU-Ultra `v4.3.0`, KernelSU-Next `v3.4.2` |
| PixelOS LKM image | `kernelsu.ko`, `ksud`, `ksuinit` built from source (`build-sukisu.sh` in the release) | SukiSU-Ultra `v4.3.0-r2` at `645ef9860b9b7f900bb5d1b27e224f2c311d39c0` |
| Manager APKs | unmodified upstream release assets, GPL-3.0; sources at [SukiSU-Ultra `v4.3.0`](https://github.com/SukiSU-Ultra/SukiSU-Ultra/tree/v4.3.0) and [KernelSU-Next `v3.4.2`](https://github.com/KernelSU-Next/KernelSU-Next/tree/v3.4.2) | SHA-256 equal to the upstream assets: `a928eb57…`, `774a5511…` |

`patches/0001-susfs-android13-5.15.patch` is the upstream patch set applied to `android13-5.15-2024-07_r1`. Three include-block hunks of the upstream `50_add_susfs_in_gki-android13-5.15.patch` do not apply to 5.15.149, because the file headers around them changed between sublevels; this repository carries the same two `#include <linux/susfs_def.h>` insertions and the `CL_COPY_MNT_NS` block placed by hand, and everything else is unchanged. The regenerated patch applies with zero rejects against the pinned tree, which CI re-checks on every build.

`build.yml` patches the stock `init_boot_a.bin` (the generic Android ramdisk only) downloaded from the stock firmware release [mblu21-stock-U01005-20261031](https://github.com/tickernelz/android_stock_meizu_mblu21/releases/tag/mblu21-stock-U01005-20261031) and checked against SHA-256 `d07159a1…` before use, so the LKM images rebuild reproducibly without keeping a stock image in this tree.

## Build

GitHub Actions builds everything; nothing here needs a local machine. Dispatch the workflow with a `release_tag` to publish pre-releases, or push to `main` to only run the checks.

`scripts/kernel_release.sh stamp` replaces `scripts/setlocalversion` in the synced tree, so the kernel reports the stock release format instead of Kleaf's unstamped `-maybe-dirty`; `kernel_release.sh check` fails the build when `Linux version` in `Image` carries `maybe-dirty` or differs from the expected string. `apply_root.sh` writes the driver version code into the copied driver (SukiSU-Ultra: `40000 + commits - 2815`; BakaSU: `30000 + commits + 700`, the upstream formulas), because the Kleaf sandbox has no git history to count. Every kernel variant adds `CONFIG_OVERLAY_FS=y` and `CONFIG_TMPFS_XATTR=y` to `gki_defconfig` and fails when the built `.config` lacks either. `verify_image.py --cpio-entry` decompresses an `init_boot` ramdisk (lz4 legacy, gzip or raw cpio) and requires exact cpio entry names, so a patched `init_boot` without `kernelsu.ko` fails whatever the compressor did. CI signs `boot-<variant>.img` with the public test key (`AVB_ALGORITHM=SHA256_RSA4096`); for the phone, run `replace_boot_kernel.sh` on `Image-<variant>` from the artifact with your own RSA-2048 key.

Locally, with the pieces available:

```sh
scripts/sync_sources.sh "$HOME/gki" be074b05e5aff5eb16a848fb3aaab2f73d687cb6 8
scripts/kernel_release.sh stamp "$HOME/gki/common" be074b05e5aff5eb16a848fb3aaab2f73d687cb6 8 1
scripts/apply_root.sh "$HOME/gki" https://github.com/SukiSU-Ultra/SukiSU-Ultra 1cfa57340590971cba7521ed536da8ebbedc5f0a patches/0001-susfs-android13-5.15.patch "$(printf '%s\n' CONFIG_KSU=y CONFIG_KSU_SUSFS=y CONFIG_KPM=y)" builtin
cd "$HOME/gki" && tools/bazel run --config=fast //common:kernel_aarch64_dist -- --dist_dir="$HOME/dist" && cd -
scripts/kernel_release.sh check "$HOME/dist/Image" 5.15.149-android13-8-00008-gbe074b05e5af-ab1
scripts/replace_boot_kernel.sh boot_a.bin "$HOME/dist/Image" <your-avb-key.pem> boot-sukisu-ultra.img
python3 scripts/module_abi.py check --imports abi/vendor_dlkm.imports.tsv --module-exports abi/vendor_boot.exports.tsv abi/vendor_dlkm.exports.tsv abi/system_dlkm.exports.tsv --symvers "$HOME/dist/kernel_aarch64_Module.symvers" --self-test
```

KPM boot image (the kernel is plain `gki_defconfig`, no root driver; `--config=fast` is left out so LTO stays full like the stock kernel):

```sh
scripts/sync_sources.sh "$HOME/gki" be074b05e5aff5eb16a848fb3aaab2f73d687cb6 8
cd "$HOME/gki" && tools/bazel run //common:kernel_aarch64_dist -- --dist_dir="$HOME/dist" && cd -
scripts/patch_kpm.sh "$HOME/dist/Image" Image-kpm
scripts/replace_boot_kernel.sh boot_a.bin Image-kpm <your-avb-key.pem> boot-kpm.img
```

`patch_kpm.sh` runs `kptools-linux` with the pinned `kpimg` from `SukiSU_KernelPatch_patch` 0.14.0 and fails unless the output grew by the payload and `kptools` lists it as patched; the release's own `patch_linux` binary writes an image without the payload, which is what hung the phone on 2026-11-03. `replace_boot_kernel.sh` keeps the stock header, AVB salt and properties, and signs with SHA256_RSA2048 (`AVB_ALGORITHM` overrides it) at rollback index location 1 (the `boot` chain slot in `vbmeta_a`). The build took 13 minutes at 4 CPUs and peaked at 24 GB of memory.

`scripts/bootimg.py` is a self-contained boot header v3/v4 packer; packing the stock kernel with it reproduces the stock `boot` and `init_boot` images byte for byte, which is the check that keeps it honest.

## License

The kernel and the patches applied to it are GPL-2.0; see `LICENSE`. The build scripts and the ABI tooling in this repository are GPL-2.0 as well. Artifacts built from it are distributed under the same terms with the sources and pins in the table above.
