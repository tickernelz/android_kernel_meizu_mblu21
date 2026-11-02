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
| [docs/ROOT.md](docs/ROOT.md) | **Root tutorial**: prerequisites, bootloader unlock, download-mode writes, manager app, proving root, SUSFS setup, restore to stock, troubleshooting |
| [docs/HARDWARE-2026-11-02.md](docs/HARDWARE-2026-11-02.md) | Hardware session results: which partitions AVB verifies, what was flashed, root evidence, live partition hashes, known gaps |
| [README.md](README.md) | This page: what is built, how it is validated, provenance, build instructions |

## Status

The **LKM path is tested on hardware**: both `init_boot` images boot and give root on a real mBlu 21, and the SUSFS guard module survives a reboot (details in [docs/HARDWARE-2026-11-02.md](docs/HARDWARE-2026-11-02.md)).

The **kernel path (`boot-<variant>.img`) is still UNTESTED.** Those images are built and pass the static ABI gate below, but no image signed with a foreign key has ever been written to `boot_a`. `vbmeta_a` chains `boot` to a Meizu key, so a rebuild is expected to be rejected; that expectation is unmeasured, which is why the CI releases stay pre-releases with `UNTESTED` in the name.

## Two paths

| Path | What is flashed | Kernel changed | Root | SUSFS (root hiding) |
|---|---|---|---|---|
| LKM (**tested**) | `init_boot` | no | kernel module loaded by the patched ramdisk | SukiSU-Ultra: yes, via the guard module. KernelSU-Next: yes, same guard module |
| Kernel (untested) | `boot` | yes | driver built into the kernel | SukiSU-Ultra: yes, kernel-side SUSFS patch. KernelSU-Next: no kernel patch needed; SUSFS comes from its `susfs_guard_lkm.ko` |

LKM path status per variant:

| Variant | LKM for `android13-5.15` | Patched `init_boot` |
|---|---|---|
| KernelSU-Next | `aarch64_android13-5.15_kernelsu.ko` from release `v3.4.2` | patched on the CI host with the official `ksud-x86_64-unknown-linux-musl` (`ksud boot-patch --kmi android13-5.15`) from the stock `init_boot_a.bin` |
| SukiSU-Ultra | `lkm-aarch64-android13-5.15_kernelsu.ko` from release `v4.3.0` | patched **on the phone** with the Android `ksud` that ships in `v4.3.0`; the result is attached to the `mblu21-root-20261102` release |

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

Two kinds of release:

| Release | Contents |
|---|---|
| `mblu21-root-20261102` | **Tested on hardware.** `init_boot-sukisu-ultra-lkm.img` and `init_boot-kernelsu-next-lkm.img` (both boot, both give root), the stock `init_boot_a`/`boot_a` images for restore, the SUSFS guard module (`susfs_guard_lkm.ko` plus `susfs_guard_lkm-module.zip`), the SukiSU-Ultra manager APK, the patch logs, and `SHA256SUMS` |
| `<variant>-<date>` (CI pre-release) | One per root variant, built by `build.yml`: `boot-<variant>.img` (untested), `init_boot-<variant>-lkm.img`, the ABI reports, `config-report.txt`, `lkm-<variant>.log` |

## Install

**The full procedure, including bootloader unlock and the download-mode writes this phone requires, is [docs/ROOT.md](docs/ROOT.md).** This section is the short form.

Prerequisites:

- Unlocked bootloader. `vbmeta` on this phone must stay Meizu-signed even when unlocked, so nothing here replaces it; `init_boot` is the one chain partition whose verification is not enforced.
- A full stock backup. `boot_a.bin` and `init_boot_a.bin` from the phone are the only reliable way back. Both are attached to `mblu21-root-20261102` as well.
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
| KernelSU-Next | `KernelSU_Next_v3.4.2_33355-release.apk` from `KernelSU-Next/KernelSU-Next` release `v3.4.2` |

### Path A - kernel with the driver built in (untested)

```sh
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec w boot_a boot-sukisu-ultra.img reset
```

Expected to be rejected by the bootloader, because `vbmeta_a` chains `boot` to a Meizu key. Not measured; see [docs/HARDWARE-2026-11-02.md](docs/HARDWARE-2026-11-02.md).

### Root hiding (SUSFS)

```sh
adb push susfs_guard_lkm-module.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/susfs_guard_lkm-module.zip'
adb reboot
```

Works on either LKM variant. Steps and verification commands are in [docs/ROOT.md](docs/ROOT.md#6-root-hiding-for-banking-apps-susfs).

## Back to stock

```sh
cd ~/tools/linux
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec w init_boot_a stock-init_boot_a.img reset
```

Flashing only the partition you changed is enough. If you also replaced `boot_a`, write `stock-boot_a.img` back the same way. Userdata is untouched by both operations.

## What is not touched

- `vendor_boot`: recovery and the first-stage ramdisk stay as shipped. Recovery images live in [android_device_meizu_mblu21-recovery](https://github.com/tickernelz/android_device_meizu_mblu21-recovery), but note that this bootloader verifies `vendor_boot` against a Meizu key, so a foreign recovery does not currently load ([docs/HARDWARE-2026-11-02.md](docs/HARDWARE-2026-11-02.md)).
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
cd "$HOME/gki" && tools/bazel run --config=fast //common:kernel_aarch64_dist -- --dist_dir="$HOME/dist"
scripts/make_boot.sh "$HOME/dist/Image" boot-sukisu-ultra.img . 67108864
python3 scripts/module_abi.py check --imports abi/vendor_dlkm.imports.tsv --module-exports abi/vendor_boot.exports.tsv abi/vendor_dlkm.exports.tsv abi/system_dlkm.exports.tsv --symvers "$HOME/dist/kernel_aarch64_Module.symvers" --self-test
```

`scripts/bootimg.py` is a self-contained boot header v3/v4 packer; packing the stock kernel with it reproduces the stock `boot` and `init_boot` images byte for byte, which is the check that keeps it honest.

## License

The kernel and the patches applied to it are GPL-2.0; see `LICENSE`. The build scripts and the ABI tooling in this repository are GPL-2.0 as well. Artifacts built from it are distributed under the same terms with the sources and pins in the table above.
