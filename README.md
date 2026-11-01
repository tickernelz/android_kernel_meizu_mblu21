# Kernel and root for Meizu mBlu 21 (M416H)

Kernel sources and a GitHub Actions pipeline that produce two flashable images for the Meizu mBlu 21: a GKI `boot` image with a root driver built in, and an `init_boot` image that loads root as a loadable module. Two root implementations are built: SukiSU-Ultra and KernelSU-Next.

| | |
|---|---|
| SoC | Unisoc T606 (UMS9230), board `ums9230_6h10` |
| Stock kernel | GKI `5.15.149-android13-8-00008-gbe074b05e5af-ab12096863` (KMI `android13-5.15`) |
| Source base | `android.googlesource.com/kernel/common`, tag `android13-5.15-2024-07_r1`, commit `be074b05e5aff5eb16a848fb3aaab2f73d687cb6` |
| `boot` partition | 67,108,864 bytes, boot header v4, kernel only (stock kernel 47,172,096 bytes) |
| `init_boot` partition | 8,388,608 bytes, boot header v4, ramdisk 2,155,827 bytes in the stock image |
| `vendor_boot` | not touched by anything here; recovery and first-stage modules stay stock |

## Status

**UNTESTED.** No image from this repository has been booted on a phone. Every release is a pre-release with `UNTESTED` in its name. The only proof so far is the static gate described below, which runs in CI on every build and is a hard failure.

## Two paths

| Path | What is flashed | Kernel changed | Root | SUSFS (root hiding) |
|---|---|---|---|---|
| LKM | `init_boot` | no | kernel module loaded by the patched ramdisk | SukiSU-Ultra: no. KernelSU-Next: yes, through its own `susfs_guard_lkm.ko` |
| Kernel | `boot` | yes | driver built into the kernel | SukiSU-Ultra: yes, kernel-side SUSFS patch. KernelSU-Next: no kernel patch needed; SUSFS comes from its `susfs_guard_lkm.ko`, attached to the release |

LKM path status per variant:

| Variant | LKM for `android13-5.15` | Patched `init_boot` in the release |
|---|---|---|
| KernelSU-Next | `aarch64_android13-5.15_kernelsu.ko` from release `v3.4.2` | yes: patched on the CI host with the official `ksud-x86_64-unknown-linux-musl` (`ksud boot-patch --kmi android13-5.15`) from the stock `init_boot_a.bin` |
| SukiSU-Ultra | `lkm-aarch64-android13-5.15_kernelsu.ko` from release `v4.3.0` | no: SukiSU-Ultra publishes `ksud` only for Android, and its `ksud` source does not build for a Linux host at `v4.3.0` (the `feature` module needs Android-only modules). The image is made by the manager app on the phone, steps below |

Pick one path. Flashing both is not a supported combination.

Why the two implementations differ here:

- SukiSU-Ultra ships SUSFS support in its `builtin` branch (its Kconfig defines `KSU_SUSFS`), but the hiding itself needs the `susfs4ksu` kernel patch, so that path is built with `patches/0001-susfs-android13-5.15.patch` applied.
- KernelSU-Next keeps its SUSFS implementation in a loadable module (`susfs_guard_lkm.ko`, built from `kernel/susfs/` in its tree), so the kernel for that variant carries only the root driver and needs no source patch.

## Static validation

The phone's 113 `vendor_dlkm` modules were built against the stock kernel and carry a `__versions` section: the CRC of every symbol they import. A kernel whose symbol CRCs differ from the stock kernel loads those modules only by luck; a mismatch on the symbols they use is what turns a custom kernel into a bootloop.

`scripts/module_abi.py` decodes `__versions` and `__ksymtab` out of every stock module, stores the result as derived text in `abi/` (no vendor binaries are redistributed), and compares it against the built kernel's `Module.symvers`:

- 113 `vendor_dlkm` modules, 6,621 imported symbols, 489 symbols exported between those modules
- 2 `system_dlkm` modules, 151 imported symbols
- A symbol imported from another stock module is skipped: that binary does not change
- `--self-test` perturbs half of the CRCs and drops a tenth of the imports, then asserts the checker reports exactly those failures. Without it, a checker that always prints zero would look identical to a good kernel.

CI fails the build on any mismatch or missing symbol, so `0 mismatches / 0 missing` in the job summary means the checker ran and found nothing, not that it was skipped.

What this does **not** prove: that the kernel boots, that the bootloader accepts the image, that SUSFS actually hides anything from a given app, or that the vendor modules work at runtime. Those are runtime facts and are unverified until the images run on hardware.

## Releases

Each release holds, per variant:

| File | Partition |
|---|---|
| `boot-<variant>.img` | `boot` |
| `boot-<variant>.img.sha256` | - |
| `init_boot-<variant>-lkm.img` | `init_boot` (KernelSU-Next only) |
| `init_boot-<variant>-lkm.img.sha256` | - |
| `susfs_guard_lkm.ko` | SUSFS module for KernelSU-Next, loaded by its manager |
| `abi-vendor_dlkm.txt`, `abi-system_dlkm.txt` | module ABI report of that build |
| `config-report.txt` | kernel configuration of the built image |
| `lkm-<variant>.log` | how the init_boot image was patched |

## Install

Prerequisites:

- Unlocked bootloader. The stock `boot` and `init_boot` are AVB chain partitions signed by Meizu; a rebuilt image cannot carry that signature, so it is signed with the public AOSP test key instead, which only an unlocked bootloader accepts.
- A full stock backup. `boot_a.bin` and `init_boot_a.bin` from the phone are the only reliable way back. Keep them.
- `adb` and `fastboot`.

Verify a download first:

```sh
sha256sum -c boot-sukisu-ultra.img.sha256
```

### Path A - kernel with the driver built in

```sh
adb reboot bootloader
fastboot getvar current-slot
fastboot flash boot boot-sukisu-ultra.img
fastboot reboot
```

The device is A/B. To cover both slots:

```sh
fastboot flash boot_a boot-sukisu-ultra.img
fastboot flash boot_b boot-sukisu-ultra.img
```

After the first boot, install the matching manager app on the phone:

| Variant | Manager |
|---|---|
| SukiSU-Ultra | `SukiSU_v4.3.0_41100-release.apk` from `SukiSU-Ultra/SukiSU-Ultra` release `v4.3.0` |
| KernelSU-Next | `KernelSU_Next_v3.4.2_33355-release.apk` from `KernelSU-Next/KernelSU-Next` release `v3.4.2` |

### Path B - init_boot with the module left to the ramdisk

`init_boot` carries only the generic ramdisk; the stock kernel stays in place.

**KernelSU-Next** (image ready in the release):

```sh
sha256sum -c init_boot-kernelsu-next-lkm.img.sha256
adb reboot bootloader
fastboot flash init_boot init_boot-kernelsu-next-lkm.img
fastboot reboot
```

Then install `KernelSU_Next_v3.4.2_33355-release.apk`.

**SukiSU-Ultra** (patched on the phone, because no host tool exists):

1. Install `SukiSU_v4.3.0_41100-release.apk` on the phone. Root is not needed for this step.
2. Copy the stock `init_boot_a.bin` to the phone: `adb push init_boot_a.bin /sdcard/Download/init_boot.img`.
3. In the SukiSU-Ultra manager, open the install screen, choose "Select a file", pick `/sdcard/Download/init_boot.img`, and choose the KMI `android13-5.15` when asked.
4. The manager writes the patched image to `/sdcard/Download/` (file name starts with `kernelsu_`). Pull it: `adb pull /sdcard/Download/kernelsu_patched_<date>.img`.
5. Flash it:

```sh
adb reboot bootloader
fastboot flash init_boot kernelsu_patched_<date>.img
fastboot reboot
```

The manager menu labels can change between app versions; if they do, the official guide is <https://kernelsu.org/guide/installation.html> ("Patch boot.img with the manager"), which SukiSU-Ultra follows.

## Back to stock

```sh
adb reboot bootloader
fastboot flash boot boot_a.bin
fastboot flash boot_b boot_a.bin
fastboot flash init_boot init_boot_a.bin
fastboot flash init_boot_b init_boot_a.bin
fastboot reboot
```

Flashing only the partition you changed is enough; both lines are given because a slot switch would otherwise bring the modified image back.

## What is not touched

- `vendor_boot`: recovery and the first-stage ramdisk and modules stay exactly as shipped, so TWRP or OrangeFox work from [android_device_meizu_mblu21-twrp](https://github.com/tickernelz/android_device_meizu_mblu21-twrp).
- `vendor_dlkm`, `system_dlkm`, `vendor`, `odm`, `dtbo`, `vbmeta*`: untouched. Nothing here needs a disabled verification chain beyond the unlocked bootloader.
- The phone itself: nothing in this repository writes to a device; images are built from sources and files in this repository.

## Provenance

| Component | Source | Pin |
|---|---|---|
| Kernel | `android.googlesource.com/kernel/common` | tag `android13-5.15-2024-07_r1` (`be074b05e5af`) via manifest branch `common-android13-5.15-2024-07` |
| SukiSU-Ultra driver (kernel path) | `github.com/SukiSU-Ultra/SukiSU-Ultra` | `builtin` at `b16e899a555e9b96aa1225f049cd7274820ca5b8` |
| KernelSU-Next driver (kernel path) | `github.com/KernelSU-Next/KernelSU-Next` | `dev` at `cefb048b069b7439fb4020d043de2d338dbc00fa` |
| SUSFS patch | `gitlab.com/simonpunk/susfs4ksu` | `gki-android13-5.15` at `3f3073a9f76247af765bfeba7908f4d3c580f2bc` |
| LKM images | flavour release assets plus a host build of `ksud` | SukiSU-Ultra `v4.3.0`, KernelSU-Next `v3.4.2` |

`patches/0001-susfs-android13-5.15.patch` is the upstream patch set applied to `android13-5.15-2024-07_r1`. Three include-block hunks of the upstream `50_add_susfs_in_gki-android13-5.15.patch` do not apply to 5.15.149, because the file headers around them changed between sublevels; this repository carries the same two `#include <linux/susfs_def.h>` insertions and the `CL_COPY_MNT_NS` block placed by hand, and everything else is unchanged. The regenerated patch applies with zero rejects against the pinned tree, which CI re-checks on every build.

`stock/init_boot_a.bin` is the stock ramdisk partition from the phone, kept here so the LKM images can be rebuilt reproducibly. It contains the generic Android ramdisk only.

## Build

GitHub Actions builds everything; nothing here needs a local machine. Dispatch the workflow with a `release_tag` to publish pre-releases, or push to `main` to only run the checks.

Locally, with the pieces available:

```sh
scripts/sync_sources.sh "$HOME/gki" be074b05e5aff5eb16a848fb3aaab2f73d687cb6 8
scripts/apply_root.sh "$HOME/gki" https://github.com/SukiSU-Ultra/SukiSU-Ultra b16e899a555e9b96aa1225f049cd7274820ca5b8 patches/0001-susfs-android13-5.15.patch CONFIG_KSU=y
cd "$HOME/gki" && tools/bazel build --config=fast //common:kernel_aarch64_dist
scripts/make_boot.sh "$HOME/gki/out/dist/Image" boot-sukisu-ultra.img . 67108864
python3 scripts/module_abi.py check --imports abi/vendor_dlkm.imports.tsv --module-exports abi/vendor_dlkm.exports.tsv --symvers "$HOME/gki/out/dist/Module.symvers" --self-test
```

`scripts/bootimg.py` is a self-contained boot header v3/v4 packer; packing the stock kernel with it reproduces the stock `boot` and `init_boot` images byte for byte, which is the check that keeps it honest.

## License

The kernel and the patches applied to it are GPL-2.0; see `LICENSE`. The build scripts and the ABI tooling in this repository are GPL-2.0 as well. Artifacts built from it are distributed under the same terms with the sources and pins in the table above.
