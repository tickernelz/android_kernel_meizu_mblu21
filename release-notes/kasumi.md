Status on the Meizu mBlu 21: **not tried on the phone yet.** Read [docs/ROOT-MODULES.md](https://github.com/tickernelz/android_kernel_meizu_mblu21/blob/main/docs/ROOT-MODULES.md) before using it.

Kasumi path hiding as a separate LKM on top of the SukiSU-Ultra `v4.3.0` LKM root, without SUSFS.

| File | What it is |
|---|---|
| `kasumi_lkm.ko` | built from `Rouyashiki/Kasumi` `049d5e93` in the pinned DDK image; reproducible, sha256 `cc20e3a9…` |
| `kasumi_lkm-module.zip` | KernelSU module that loads it at `post-fs-data` with `ksud insmod` |
| `kernelsu.ko` | SukiSU-Ultra `v4.3.0` `android13-5.15` LKM, the root driver this variant expects |
| `module-abi-kasumi.txt` | vermagic and symbol check against the stock kernel |
| `SHA256SUMS-kasumi` | hashes of every file above |

Kasumi refuses to load beside `susfs_guard_lkm`: uninstall the SUSFS guard module first. No hiding rules are configured without a controller (Kagami, not built here).
