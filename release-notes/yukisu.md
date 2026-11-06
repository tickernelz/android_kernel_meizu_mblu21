Status on the Meizu mBlu 21: **not tried on the phone yet.** Read [docs/ROOT-MODULES.md](https://github.com/tickernelz/android_kernel_meizu_mblu21/blob/main/docs/ROOT-MODULES.md) before using it.

YukiSU `v1.8.1` LKM root for the stock `5.15.149` kernel, without SUSFS. Kasumi path hiding and YukiZygisk are built into `kernelsu.ko`.

| File | What it is |
|---|---|
| `android13-5.15_kernelsu.ko` | the upstream YukiSU LKM |
| `android13-5.15_kernelsu.ko.sig`, `ksud-aarch64-linux-android(.sig)`, `YukiSU_v1.8.1_10680-arm64-v8a-release.apk(.asc)` | upstream release files with their GPG signatures, verified in CI against key `71B2B58C…EF67DC98` |
| `module-abi-yukisu.txt` | vermagic and symbol check against the stock kernel, signature results |
| `SHA256SUMS-yukisu` | hashes of every file above |

Do not install `susfs_guard_lkm`, a separate `kasumi_lkm.ko`, or another Zygisk beside it.
