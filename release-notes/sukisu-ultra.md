Status of this build on the Meizu mBlu 21: `boot-<variant>.img` has not been tried on a phone. The image that stopped at the logo on 2026-11-03 came from a branch whose KernelPatch step dropped the payload; this build has no such step, and the unlocked bootloader accepts a `boot` signed with another key. Use the `init_boot` LKM path; the images tested on the phone are in release `mblu21-root-20261102`.

This pre-release carries two flashable images for the `sukisu-ultra` root path:

| File | Partition | Contents |
|---|---|---|
| `boot-sukisu-ultra.img` | `boot` | GKI `5.15.149` kernel built from `android13-5.15-2024-07_r1` with the `sukisu-ultra` driver integrated; AVB footer re-signed with the public AOSP test key |

No patched `init_boot` is attached: SukiSU-Ultra ships no host-side `ksud`, so the LKM path is done by the manager app on the phone (README, Path B).

Pick one path, not both. Both require an unlocked bootloader.

Static validation attached to this release:

- `abi-vendor_boot.txt` - every symbol the 139 stock first-stage modules in `vendor_boot` import, compared against the built kernel's `Module.symvers`
- `abi-vendor_dlkm.txt` - every symbol the 113 stock `vendor_dlkm` modules import, compared against the built kernel's `Module.symvers`
- `abi-system_dlkm.txt` - the same check for the stock `system_dlkm` modules
- `config-report.txt` - kernel configuration of the built image
- `lkm-sukisu-ultra.log` - the official LKM used by the on-phone path and its vermagic

Every file has a matching `.sha256`.
