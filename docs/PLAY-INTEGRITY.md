# Play Integrity on the mBlu 21 (LineageOS 24.0)

Status: **MEETS_DEVICE_INTEGRITY** reached with a hardware keybox; **MEETS_STRONG_INTEGRITY**
not reached. Everything below was measured on the phone, not inferred.

## What is installed

| Piece | Version | Role |
|---|---|---|
| SukiSU Ultra | 4.3.0 (LKM in `init_boot`) | root, SUSFS host |
| SUSFS guard | v2.3.0-gki (`susfs_guard_lkm.ko`) | hides root, spoofs kernel strings |
| NeoZygisk | v2.4 | zygisk provider for PIF |
| Tricky Store | 1.4.1 (245-72b2e84) | replaces the key attestation chain with the keybox |
| Play Integrity Fix [INJECT] | v4.9-inject-s | spoofs build props for DroidGuard |

Files that matter:

- `/data/adb/tricky_store/keybox.xml` — the attestation keybox. The **stock AOSP software
  keybox that ships default is the reason Play Integrity returns NO_INTEGRITY**: its leaf is
  the *Android Keystore Software Attestation Root* and Google rejects software roots.
- `/data/adb/tricky_store/target.txt` — packages whose attestation is substituted:
  `com.android.vending`, `com.google.android.gms`, plus the checker packages.
- `/data/adb/tricky_store/tee_status` — `teeBroken=false` on this phone. Setting it to
  `true` makes Tricky Store synthesise the whole chain itself; measured verdict with
  `true` is **worse** (MEETS_BASIC_INTEGRITY), so keep `false`.

## Measured results

| Keybox | tee_status | Device verdict |
|---|---|---|
| stock AOSP software (default) | absent | NO_INTEGRITY |
| hardware keybox A (`1e59118f…`, Droid CA3 chain, expires 2026-11-06) | false | **MEETS_DEVICE_INTEGRITY** |
| hardware keybox A | true | MEETS_BASIC_INTEGRITY |
| hardware keybox B (`994da97a…`, expires 2026-11-04) | false | MEETS_DEVICE_INTEGRITY |
| hardware keybox B | true | MEETS_DEVICE_INTEGRITY |
| keybox `15a5128b…` ("soft" class) | false | MEETS_BASIC_INTEGRITY |

Verification command used for every row:

```bash
adb shell am force-stop com.henrikherzig.playintegritychecker
adb shell am start -n com.henrikherzig.playintegritychecker/.MainActivity
adb shell input tap 383 594        # "Make Play Integrity Request"
adb logcat -d | grep System.out    # prints the raw verdict JSON
```

`appRecognitionVerdict` is `PLAY_RECOGNIZED`, `appLicensingVerdict` is `LICENSED`,
`playProtectVerdict` is `NO_ISSUES`. The raw JSON carries
`deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"]`.

KeyAttestation shows the substituted chain: leaf `O=TEE, CN=…`, issuer
`O=Google LLC, CN=Droid CA3`, root `CN=Key Attestation CA1`, and `Bootloader is locked`
(the keybox's root-of-trust says locked even though the phone is unlocked).

## Why STRONG is not reached

STRONG_INTEGRITY needs the attestation to come from a keybox Google has **not** seen used
by many devices, together with a device whose build fingerprint matches the certified
device the keybox belongs to. A keybox that circulates publicly is used by thousands of
devices, so the server verdict stops at DEVICE. That is a server-side decision; nothing in
the ramdisk or props changes it.

Attempts that did not help (measured, not guessed): `teeBroken=true`, the generate-mode
target list (`pkg!`), the "soft"-class keybox, clearing `key_dbs`, restarting
`keystore2`/`TrickyStore` instead of rebooting, and swapping PIF's fingerprint
(`google/bluejay_beta/…`, SECURITY_PATCH 2026-10-05).

## Reproducing on a fresh install

1. Install NeoZygisk, Tricky Store, Play Integrity Fix, then SukiSU root (LKM, init_boot).
2. Replace `/data/adb/tricky_store/keybox.xml` with a **hardware** keybox.xml whose leaf
   chains to `CN=Droid CA3`; keep `/data/adb/tricky_store/tee_status` at
   `teeBroken=false`.
3. Keep `com.android.vending` and `com.google.android.gms` in `target.txt`.
4. Reboot. Restarting only `keystore2` is not enough for PIF's prop spoof.

## Honest limits

- DEVICE integrity is what most banking apps consume; STRONG is not available from a
  shared keybox.
- Do not put a keybox in this repository: it is somebody else's private key material.
