# Root variants without SUSFS: YukiSU, Kasumi, YukiZygisk

Three optional root variants built by [`root-modules.yml`](../.github/workflows/root-modules.yml). They are separate from the SUSFS variants of `build.yml` (`sukisu-ultra`, `kernelsu-next` with `susfs_guard_lkm`), which stay the default and are not changed. None of the three has been run on the phone yet.

All three use the LKM path: the stock `5.15.149` kernel stays in `boot`, and root comes from a loadable module. The phone only boots a Meizu-signed `boot` (see [AVB-POLICY.md](AVB-POLICY.md)), so a kernel with these drivers built in is not an option; YukiSU itself is LKM-only (`CONFIG_KSU=m`; its docs say built-in mode is not supported).

## Pick one

| Variant | Root driver | Hiding | Zygisk | Do not combine with |
|---|---|---|---|---|
| `yukisu` | YukiSU `v1.8.1` `android13-5.15_kernelsu.ko` | Kasumi built into `kernelsu.ko` | YukiZygisk built into `kernelsu.ko` | `susfs_guard_lkm`, a separate `kasumi_lkm.ko` (YukiSU refuses to load it), another Zygisk |
| `kasumi` | SukiSU-Ultra `v4.3.0` LKM (the same file as the `sukisu-ultra` LKM path) | `kasumi_lkm.ko` built from source, loaded by `kasumi_lkm-module.zip` | none | `susfs_guard_lkm` and its module zip |
| `yukizygisk` | any of the LKM roots above | none of its own | `YukiZygisk-v0.3.0-10136` module zip | every other Zygisk, including YukiSU's built-in one |

One root implementation at a time. Moving from a SUSFS variant to `yukisu` or `kasumi` means uninstalling the SUSFS guard module first.

### Why Kasumi and SUSFS exclude each other

Kasumi refuses to initialise while `pathmask`, `procguard`, `nomount`, `susfs_guard_lkm` or `hybridmount` is loaded, or when the running kernel's IKCONFIG contains `CONFIG_KSU_SUSFS=y` (Kasumi README, "API 18 conflict guard"; list in `src/core/kasumi_module_guard.c`). Once loaded, it rejects those modules too. The SUSFS variants load `susfs_guard_lkm`, so Kasumi only runs on a root path without it. The stock kernel does carry IKCONFIG (`CONFIG_IKCONFIG_PROC=y`, 6,949 lines), but none of `CONFIG_KSU_SUSFS`, `CONFIG_NOMOUNT` or `CONFIG_HYBRIDMOUNT` is in it, so the IKCONFIG test passes on the LKM path; CI asserts this on every run. YukiSU carries the same guard (`kernel/feature/sucompat_module_guard.c`) and adds `kasumi_lkm` to the list, because its `kernelsu.ko` already contains Kasumi (imported from Kasumi `e648702b`).

## Artifacts and pins

| Variant | Artifact | Source | sha256 |
|---|---|---|---|
| `yukisu` | `android13-5.15_kernelsu.ko` + `.sig` | release [`v1.8.1`](https://github.com/Rouyashiki/YukiSU/releases/tag/v1.8.1) | `b74c9742…` |
| `yukisu` | `ksud-aarch64-linux-android` + `.sig` | same | `7033700c…` |
| `yukisu` | `YukiSU_v1.8.1_10680-arm64-v8a-release.apk` + `.asc` | same | `42c7bdb5…` |
| `kasumi` | `kasumi_lkm.ko` | [`Rouyashiki/Kasumi`](https://github.com/Rouyashiki/Kasumi) at `049d5e93f0e2`, built with `scripts/build_kasumi.sh` in `ghcr.io/ylarod/ddk-min@sha256:9e68cd9f…` (`android13-5.15-20260828`) | `cc20e3a9…` |
| `kasumi` | `kernelsu.ko` | SukiSU-Ultra [`v4.3.0`](https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases/tag/v4.3.0) `lkm-aarch64-android13-5.15_kernelsu.ko` | `c8251322…` |
| `yukizygisk` | `YukiZygisk-v0.3.0-10136-all-kmi-arm64-v8a.zip` | release [`ci-41973134583`](https://github.com/Rouyashiki/YukiZygisk/releases/tag/ci-41973134583) (YukiZygisk has no versioned releases) | `710ba1e9…` |
| `yukizygisk` | `lkm/android13-5.15_yukizygisk.ko` inside that zip | same | `d6845bcf…` |

Full hashes are in the workflow's `env`; CI fails on any difference. The three YukiSU files are also checked against their detached GPG signatures with the key in [`keys/yukisu-anatdx.asc`](../keys/yukisu-anatdx.asc) (primary fingerprint `71B2 B58C 2A54 3472 BE0D A0D8 F580 A2CE EF67 DC98`), and the YukiZygisk zip against the release's own `SHA256SUMS` and the per-file `.sha256` inside the zip.

Kasumi publishes no binaries, so CI builds it. The build is reproducible: three local builds (as root and as a normal user) and the CI build give the same `cc20e3a9…`, and CI fails if a rebuild differs.

## What CI checks per variant

`scripts/module_abi.py lkm` compares each module with the **stock** kernel it will be loaded into: `boot_a.bin` from the stock firmware release (sha256 `3a78e139…`), kernel extracted with `scripts/bootimg.py kernel`, symbol table recovered with `kallsyms-finder` (`vmlinux-to-elf` 1.4.0, hash-pinned in `scripts/kallsyms-requirements.txt`).

- **vermagic**: the flags must equal the stock kernel's (`SMP preempt mod_unload modversions aarch64`, read from the stock image). The kernel skips the release part only when the module has an allocated `__versions` section, so the checker accepts any `5.15.*` release only in that case and otherwise requires the stock release exactly. All modules here say `5.15.202-android13-5.15.202_r00-dirty` and carry an allocated but empty `__versions` section, so the release is skipped and no CRC is checked at load time.
- **imports**: every undefined symbol is classified as exported by the kernel (`__ksymtab_` present), present in kallsyms only, or missing. Any missing symbol fails the job. "Kallsyms only" passes but is listed: plain `insmod` cannot resolve those, so the module needs a loader that resolves them from kallsyms (`ksud insmod`, KernelSU's own loader for `kernelsu.ko`, YukiZygisk's `viola`).
- **`is_subdir`**: always reported for the kernel and for every module that imports it.
- **IKCONFIG**: the stock kernel's embedded config must not set `CONFIG_KSU_SUSFS`, `CONFIG_NOMOUNT` or `CONFIG_HYBRIDMOUNT`, which would make Kasumi (standalone or inside YukiSU) refuse to start.
- **self-test**: removes a tenth of each module's resolvable imports from the symbol table and asserts the checker reports exactly those as missing, so a checker that always passes is caught.

Measured on the stock kernel (149,066 kallsyms entries, 8,151 exports):

| Module | Imports | Exported | Kallsyms only | Missing |
|---|---|---|---|---|
| YukiSU `kernelsu.ko` v1.8.1 | 380 | 273 | 107 | 0 |
| `kasumi_lkm.ko` 049d5e93 | 183 | 177 | 6 (`cancel_work d_lookup deactivate_super kernel_read seq_read_iter vma_set_file`) | 0 |
| `yukizygisk.ko` v0.3.0-10136 | 148 | 147 | 1 (`is_subdir`) | 0 |
| SukiSU-Ultra `kernelsu.ko` v4.3.0 (reference) | 249 | 166 | 83 | 0 |
| `susfs_guard_lkm.ko` v3.4.2 (reference) | 97 | 89 | 8 | 0 |

### `is_subdir` and the 2026-11-06 panic

`is_subdir` exists in the stock kernel (`T 0xffffffc0085832a0`) but is **not exported**: there is no `__ksymtab_is_subdir`. `yukizygisk.ko` imports it, and it is the only one of its 148 imports that is not exported. The pstore of the 2026-11-06 bootloop shows `yukizygisk: Unknown symbol is_subdir (err -2)`, which is the kernel's own loader failing on a non-exported symbol, and then `yukizygisk.ko loads too long time, panic timeout = 2000 ms` from Unisoc's `native_hang_monitor`.

[INFERENCE] The `Unknown symbol` line means YukiZygisk's loader (`bin/viola`, which resolves symbols from `/proc/kallsyms` and falls back to `init_module` when it cannot) handed the module to the kernel without relocating `is_subdir`. Why it fell back on that boot, and whether `susfs_guard_lkm` was involved, is not measured; the phone was reset before it could be checked. The hang monitor's 2000 ms limit applies to any module load during boot.

## Feature differences against the SUSFS variants

- `yukisu` and `kasumi` drop SUSFS (`susfs_guard_lkm`, `ksud susfs`). Path hiding comes from Kasumi instead, which is configured differently: YukiSU's manager has Kasumi hide-rule management; for the standalone `kasumi_lkm.ko` the reference controller is [Kagami](https://github.com/Rouyashiki/Kagami), which has no published release and is not built here, so on SukiSU-Ultra the module loads and enforces its conflict guard, but no hiding rules are configured until a controller sets them.
- Size: YukiSU `kernelsu.ko` is 1,566,224 bytes (SukiSU-Ultra 666,288), because Kasumi and YukiZygisk are built in.
- Boot time and load time are not measured yet (see below).

## Install (after Zhafron allows a phone test)

Same flow as [ROOT.md](ROOT.md) Path B: the manager app patches `init_boot` on the phone, then the patched image is written with `spd_dump`. None of these variants has a host-side patcher here (`ksud-aarch64-linux-android` runs on Android only).

- `yukisu`: install the YukiSU APK, let it patch the stock `init_boot_a.bin` using `android13-5.15_kernelsu.ko` from this release, flash, reboot.
- `kasumi`: root with the `sukisu-ultra` LKM path and make sure `susfs_guard_lkm` is not installed. Load `kasumi_lkm.ko` by hand first and time it (test plan below); only then `ksud module install kasumi_lkm-module.zip`. The module loads `kasumi_lkm.ko` in `post-fs-data` with `/data/adb/ksud insmod` and logs to `/data/adb/ksu/log/kasumi.log`; it skips the load and logs why when a conflicting module is present.
- `yukizygisk`: on a KernelSU-family root with no other Zygisk (on `yukisu`, switch off the built-in YukiZygisk first), load `yukizygisk.ko` by hand first and time it (test plan below). Only after that install the zip from the manager: installing it schedules `post-fs-data.sh`, which loads the module during the next boot, the path that panicked on 2026-11-06.

## Phone test plan and recovery

Lock `~/re/mblu21/.phone.lock` for the whole session.

Before flashing anything:

1. Have the stock `init_boot_a.bin` (`d07159a1…`) and `boot_a.bin` (`3a78e139…`) ready; `init_boot` is the only partition these variants change.
2. Recovery path A, a module stops boot: KernelSU safe mode, pressing Volume Down repeatedly while the phone boots, starts with every module disabled; then uninstall the module from the manager. This is upstream KernelSU behaviour and has not been tried on this phone or in YukiSU. Volume Down inside the stock recovery resets the phone instead (AVB-POLICY.md), so do not use recovery for this.
3. Recovery path B, always available: download mode (Volume Up + plug in) and `spd_dump … w init_boot_a init_boot_a.bin` with the stock image (README, "Back to stock"). This boots without root; the module directory under `/data/adb/modules` stays, so rooting again re-runs it until it is removed (safe mode, or a reset).

Measurements to take:

- `yukizygisk`, before the zip is installed: after a normal boot with root, `adb push yukizygisk.ko /data/local/tmp/` (from the release), then `su -c 'dmesg -c >/dev/null; time /data/adb/ksud insmod /data/local/tmp/yukizygisk.ko; dmesg | grep -i yukizygisk'`. `ksud insmod` resolves `is_subdir` from kallsyms. There must be no `Unknown symbol`, and the load must stay well below the 2000 ms `native_hang_monitor` limit. Then reboot (the module is not persistent), install the zip, and boot 3 times in a row without a panic (`/sys/fs/pstore` empty after each). If a boot with the zip installed hangs, recovery path A applies.
- `kasumi`, before the zip is installed: the same hand load and timing with `kasumi_lkm.ko` (`ksud insmod` resolves its 6 non-exported imports); `kasumi_lkm.ko` loaded from `post-fs-data` runs under the same 2000 ms limit. Then install the zip and check `rc=0 present=yes` at the end of `kasumi.log` for each of 3 boots, no panic.
- `yukisu`: root works (`su -c id`), built-in Kasumi and YukiZygisk state as shown by the manager, 3 boots without a panic.
