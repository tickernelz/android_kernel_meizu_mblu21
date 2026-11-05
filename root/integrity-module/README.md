# mblu21 integrity module

One KernelSU/Magisk zip for Play Integrity on the Meizu mBlu 21 (M416H): Tricky Store
1.4.1 handles keystore attestation, Play Integrity Fork v19 supplies the certified
fingerprint and prop cleanup, and this module owns the target list, the security patch
level and the keybox policy. It replaces the combined third-party drop-in that occupied
`/data/adb/tricky_store` and fetched a keybox over plain HTTP at boot.

| File | Purpose |
|---|---|
| `module/module.prop` | module identity: id `playintegrityfix`, version `v1.0.0` |
| `module/customize.sh` | installer: moves the old `/data/adb/modules/tricky_store` aside, keeps the keybox already on the phone, seeds the config |
| `module/post-fs-data.sh`, `module/service.sh` | source the unmodified upstream PIF scripts, then start the Tricky Store daemon from the module root |
| `module/bin/integrity.sh` | `status`, `doctor`, `verdict`, `keybox`, `targets`, `sp` |
| `module/bin/keybox.sh` | keybox completeness report and the opt-in fetch |
| `module/bin/boot-verdict.sh`, `module/bin/verdict-parse.sh` | measure the verdict 60 s after every boot and append one parsed line to `/data/adb/tricky_store/verdicts.jsonl`; it taps only when the checker has focus and records `skipped:<focus>` otherwise |
| `module/bin/fix-persist.sh` | restore `/data/property/persistent_properties` to 0600 and re-arm `persist.sys.usb.config=adb` |
| `module/bin/targets.sh`, `module/bin/sp.sh` | target list and security patch level helpers |
| `module/target.txt`, `module/security_patch.txt`, `module/pif.prop`, `module/integrity.conf` | the defaults the installer seeds |
| `module/licenses/` | upstream notices and the GPL-3.0 text |
| `build-module.sh` | downloads the pinned upstream releases and assembles the zip |
| `tests/run.sh` | shell tests for the config logic, no device needed |
| `tools/measure-spic.sh` | asks the phone for a fresh Play Integrity verdict over adb |

The module id is `playintegrityfix` on purpose: the upstream PIF companion library opens
`/data/adb/modules/playintegrityfix/classes.dex` and `/data/adb/modules/playintegrityfix/pif.prop`
by absolute path, so the module has to live there.

The Tricky Store payload keeps its upstream layout at the module root — `service.apk`,
`daemon`, `libtricky_store.so`, `machikado`, `mazoku` — because `daemon` starts
`app_process` with `-Djava.class.path=./service.apk`, so its working directory has to be the
directory that holds the APK and the shared library. Only `post-fs-data.sh`, `service.sh`
and `target.txt` collide with the PIF payload, and those are merged here.

## Build

```sh
./build-module.sh mblu21-integrity.zip
```

Both upstream artifacts are pinned by sha256 in the script and pulled from their official
releases; they are not vendored in this repository. Rebuilding is reproducible: entries
carry a fixed timestamp, so the same inputs give the same sha256.

## Install

```sh
adb push mblu21-integrity.zip /data/local/tmp/
adb shell ksud module install /data/local/tmp/mblu21-integrity.zip
adb reboot
adb shell sh /data/adb/modules/playintegrityfix/bin/integrity.sh doctor
```

`customize.sh` keeps an existing `/data/adb/tricky_store/keybox.xml` untouched and moves
every other artifact of the old module into `/data/adb/tricky_store/legacy-<stamp>/`.

## Keybox policy

`/data/adb/tricky_store/keybox.xml` is chosen by `keybox_mode` in
`/data/adb/tricky_store/integrity.conf`:

| `keybox_mode` | Behaviour |
|---|---|
| `auto` (default) | keep the keybox already on the phone; install the bundled one only when none exists |
| `existing` | never install the bundled one, whatever is there stays |
| `software` | install the bundled one, but only when the content actually differs |
| `software` | install the software keybox that ships inside the Tricky Store release, backing up the previous file next to it |

The bundled software keybox is `software-keybox.xml` in the module and inside the official
Tricky Store zip (`DeviceID="sw"`); it carries both an `ecdsa` and an `rsa` key, which is
what Play asks for. It is a self-signed test chain, not a Google-signed one.

The module never downloads a keybox by default: `auto_keybox=0` and `keybox_url` is
empty. Turning it on is an explicit decision, and `service.sh` warns every time it runs:

* an `http://` source is plain HTTP, so anything on the path can substitute the file;
* `keybox_sha256` is a change detector, not a signature, so leaving it empty trusts
  whatever arrives;
* a keybox carries another device's private attestation keys, which is why no keybox is
  vendored here and why the shipped config does not name a source.

`bin/integrity.sh keybox` reports whether the file on the phone is complete: Play asks
for both an `ecdsa` and an `rsa` key, and an `ecdsa`-only file makes Play log
`Incomplete keybox provided by overlays` and fall back to the real TEE record. That log
line, not a guess, is what `doctor` fails on.

## Security patch level

`pif.prop` spoofs `ro.build.*` inside Play Services and Play Store, so the identity Google
evaluates is the fingerprint in that file, not the ROM's own `ro.build.id`. The security
patch level therefore has to match the spoofed fingerprint's build id, and
`bin/sp.sh check` verifies exactly that: the three lines in `security_patch.txt`, the
`SECURITY_PATCH` in `pif.prop` and the `YYMMDD` stamp inside the fingerprint's build id
must agree, and the level must sit on the 5th.

```sh
adb shell sh /data/adb/modules/playintegrityfix/bin/integrity.sh sp show
adb shell sh /data/adb/modules/playintegrityfix/bin/integrity.sh sp set 2026-11-05
```

## Measure

Every boot measures itself: `service.sh` starts `bin/boot-verdict.sh`, which waits for
`sys.boot_completed`, waits another 60 s, drives Simple Play Integrity Checker and appends the
parsed result to `/data/adb/tricky_store/verdicts.jsonl`. `auto_verdict=0` in
`/data/adb/tricky_store/integrity.conf` turns that off.

```sh
adb shell sh /data/adb/modules/playintegrityfix/bin/integrity.sh verdicts 5
adb shell sh /data/adb/modules/playintegrityfix/bin/integrity.sh doctor
```

`doctor` also checks the hiding invariants: SUSFS active, no `/system/bin/su` in the default
namespace, `persistent_properties` at 0600, and `persist.sys.usb.config` still carrying `adb`.

## Measure on demand

```sh
./tools/measure-spic.sh
```

It wakes the phone, resets the Simple Play Integrity Checker, taps its request button and
prints the raw `System.out` JSON from logcat. The tap coordinates live in
`integrity.conf` (`spic_tap_x`, `spic_tap_y`).

## What this module cannot do

`MEETS_STRONG_INTEGRITY` on Android 13+ needs hardware-backed proof that the bootloader is
locked and the OS is a certified build. This phone's bootloader is unlocked. The only way
to make such a claim verify is an attestation chain signed by an unrevoked Google keybox,
which is another device's secret material. The module therefore targets
`MEETS_DEVICE_INTEGRITY` and reports whatever it measures.
