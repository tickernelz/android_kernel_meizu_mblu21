UNTESTED build. Nothing here has been booted on a phone.

This pre-release carries two flashable images for the `sukisu-ultra` root path:

| File | Partition | Contents |
|---|---|---|
| `boot-sukisu-ultra.img` | `boot` | GKI `5.15.149` kernel built from `android13-5.15-2024-07_r1` with the `sukisu-ultra` driver integrated; AVB footer re-signed with the public AOSP test key |
| `init_boot-sukisu-ultra-lkm.img` | `init_boot` | stock init_boot ramdisk with the `sukisu-ultra` LKM injection (no kernel change) |

Pick one path, not both. Both require an unlocked bootloader.

Static validation attached to this release:

- `abi-vendor_dlkm.txt` - every symbol the 113 stock `vendor_dlkm` modules import, compared against the built kernel's `Module.symvers`
- `abi-system_dlkm.txt` - the same check for the stock `system_dlkm` modules
- `config-report.txt` - kernel configuration of the built image
- `lkm-sukisu-ultra.log` - how the init_boot image was patched

Every file has a matching `.sha256`.
