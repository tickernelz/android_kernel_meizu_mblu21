# keys

`testkey_rsa4096.pem` is the **public AOSP test key** from [`external/avb/test/data/testkey_rsa4096.pem`](https://android.googlesource.com/platform/external/avb/+/refs/heads/main/test/data/testkey_rsa4096.pem), byte-identical (SHA-256 `6a224754880a57ab9cbd308267cd157d94cf05a1c8cb851aec4090e045d24121`). It is **not a release key**: anyone can sign with it, and it only gives `boot-<variant>.img` a well-formed AVB footer. The phone does not trust it; see [docs/AVB-POLICY.md](../docs/AVB-POLICY.md).
