Status on the Meizu mBlu 21: **not tried on the phone yet.** A YukiZygisk build caused a boot panic on 2026-11-06 (`Unknown symbol is_subdir`, then the 2000 ms module-load hang monitor). Read [docs/ROOT-MODULES.md](https://github.com/tickernelz/android_kernel_meizu_mblu21/blob/main/docs/ROOT-MODULES.md) and follow its test plan before enabling it at boot.

| File | What it is |
|---|---|
| `YukiZygisk-v0.3.0-10136-all-kmi-arm64-v8a.zip` | upstream module zip from release `ci-41973134583`, checked against its `SHA256SUMS` |
| `yukizygisk.ko` | the `android13-5.15` LKM from that zip, for inspection |
| `module-abi-yukizygisk.txt` | vermagic and symbol check against the stock kernel; `is_subdir` is in kallsyms but not exported |
| `SHA256SUMS-yukizygisk` | hashes of every file above |

Use with one KernelSU-family root and no other Zygisk, including YukiSU's built-in one.
