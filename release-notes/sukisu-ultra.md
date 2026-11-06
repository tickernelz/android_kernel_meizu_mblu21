Status of this build on the Meizu mBlu 21: not tried on a phone. With the bootloader unlocked, a `boot` signed with another key is logged and ignored (docs/AVB-POLICY.md); the KernelPatch step here is `scripts/patch_kpm.sh`, which refuses an image without the payload, unlike the 2026-11-03 image that stopped at the logo. The images tested on the phone are in releases `mblu21-root-20261102` and `mblu21-pixelos-root-20261106`.

This pre-release carries two flashable `boot` images from one kernel build, SukiSU-Ultra and SUSFS built in, so no `kernelsu.ko` or `susfs_guard_lkm.ko` is loaded:

| File | Partition | Contents |
|---|---|---|
| `boot-sukisu-ultra.img` | `boot` | GKI `5.15.149` kernel from `android13-5.15-2024-07_r1` with SukiSU-Ultra `builtin` at `1cfa57340590971cba7521ed536da8ebbedc5f0a`, `CONFIG_KSU_SUSFS=y` (`patches/0001-susfs-android13-5.15.patch`) and `CONFIG_KPM=y` |
| `boot-sukisu-ultra-kpm.img` | `boot` | the same kernel patched with KernelPatch 0.14.0 by `scripts/patch_kpm.sh` |

The kernel reports `5.15.149-android13-8-00008-gbe074b05e5af-ab<run number>`, the stock format, and the build fails when it does not (`config-report.txt`). Both images keep the stock `boot` header, AVB salt and properties (`scripts/replace_boot_kernel.sh`) and are signed with the public AOSP test key. Do not combine them with a root `init_boot`: write the stock `init_boot` first, because two root drivers at once are not supported.

The kernel in this build sets `CONFIG_TMPFS_XATTR=y` (not set in the stock kernel on the phone or in earlier builds here) and keeps `CONFIG_OVERLAY_FS=y`; the build fails when either line is missing from `.config` (`kernel.config` in the artifact).

The `builtin` branch, not the `v4.3.0-r2` tag, carries SUSFS: the tag's Kconfig has no `KSU_SUSFS` and it defines none of the hooks the SUSFS patch calls. The driver reports version code 41865 (`v4.2.1-1cfa5734@builtin`); the `v4.3.0-r2` manager is 41150.

Static validation attached to this release:

- `abi-vendor_boot.txt`, `abi-vendor_dlkm.txt`, `abi-system_dlkm.txt` - every symbol the stock modules import, compared against the built kernel's `Module.symvers`
- `config-report.txt` - kernel release check, KernelPatch result and the root-related configuration
- `lkm-sukisu-ultra.log` - the official LKM used by the on-phone LKM path and its vermagic

Every image has a matching `.sha256`.
