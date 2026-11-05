# Play Integrity on the mBlu 21

Every number below was measured on this phone, Meizu mBlu 21 (M416H), Android 17
(API 37) build `CP2A.260605.016`, bootloader unlocked, SukiSU-Ultra 4.3.0-r2 (LKM),
SUSFS guard v2.3.0-gki, NeoZygisk v2.4. The verdict comes from Simple Play Integrity
Checker reading the raw token from Play, not from a summary screen.

## What Google requires

Google's June 2025 verdict rework (developer.android.com/google/play/integrity/improvements,
summarised by bayton.org on 2026-09-14) states the two labels this phone cannot reach:

* `MEETS_DEVICE_INTEGRITY` requires hardware-backed evidence that the bootloader is **locked**
  and that the running OS is a **certified OEM image**.
* `MEETS_STRONG_INTEGRITY` requires that plus a security patch level from the last year on every
  partition, vendor included.
* `MEETS_BASIC_INTEGRITY` is the one label allowed on an unlocked, rooted device, as long as key
  attestation is present at all.

The bootloader of this unit cannot be locked again with its own key: `vbmeta_a` chains to the
Meizu key `d46eb3be` and `vendor_boot` to `4fce36c7`, and the 2026-11-03 attempt stopped at the
boot logo. The only way to produce a verifying "locked" claim would be an attestation chain signed
by an unrevoked Google keybox, which is another device's private key material; no such keybox is
carried by this project and none was fetched.

## Result

| Configuration | Keybox in use | Keystore interposer | Device verdict |
|---|---|---|---|
| Before any work: combined third-party drop-in (`AlwaysStrong [Inject]` v1.0.5) | `evokerrkey44.xml`, ecdsa only | TEESimulator | `MEETS_BASIC_INTEGRITY` |
| `mblu21-integrity` v1.0.0, `keybox_mode=existing` | `evokerrkey44.xml`, ecdsa only | Tricky Store 1.4.1 | `MEETS_BASIC_INTEGRITY` on 3 consecutive boots |
| `mblu21-integrity` v1.0.0, `keybox_mode=software` | Tricky Store's software keybox, ecdsa + rsa | Tricky Store 1.4.1 | `MEETS_BASIC_INTEGRITY` on 2 consecutive boots |
| `AlwaysStrong` restored as a cross-check | Tricky Store's software keybox, ecdsa + rsa | TEESimulator | `UNEVALUATED` twice |
| `mblu21-integrity` v1.0.0, `keybox_mode=software` (test only; shipped default is `auto`) | Tricky Store's software keybox, ecdsa + rsa | Tricky Store 1.4.1 | `MEETS_BASIC_INTEGRITY` |

`MEETS_DEVICE_INTEGRITY` was not reached in any configuration, and
`MEETS_STRONG_INTEGRITY` never appeared at all.

## Why DEVICE is unreachable here

Both interposers were tested with the same three inputs — a certified Pixel fingerprint,
a security patch level that matches it, and Play Services and Play Store in the target
list — and the verdict stayed at `MEETS_BASIC_INTEGRITY` or dropped to `UNEVALUATED`.

Play derives the device verdict from a key attestation record it asks for itself. On this
phone that record is genuine: KeyAttestation (`io.github.vvb2060.keyattestation`, a target
package) reports the real chain — `SERIALNUMBER=f92009e853b6b045` (Google's hardware
attestation root), two TEE intermediates, and a fresh leaf — with
`Bootloader is unlocked` in the attestation extension. So the bootloader state Play sees is
the hardware truth, and a hardware-backed claim of a locked bootloader needs a keybox whose
chain Google signed and whose keys have not been revoked. The phone has no such keybox.

The two keyboxes that were available behave differently and both fail:

* `evokerrkey44.xml` carries one `ecdsa` key and a four-certificate chain and no `rsa`
  key. Play asks for both, logs `W/KeyProviderManager: Incomplete keybox provided by
  overlays`, and falls back to the real TEE record.
* The software keybox that ships inside the Tricky Store release (`DeviceID="sw"`) does
  carry `ecdsa` and `rsa`, but its chain is self-signed, so it cannot stand in for a
  Google-signed one. With it in place Play returned `UNEVALUATED` instead of a verdict.

`MEETS_STRONG_INTEGRITY` additionally requires hardware-backed proof, so it is out of
reach for the same reason and was never pursued.

## Tricky Store 1.4.1 does not inject on this ROM

The module runs, but it has no effect here, and that is measured, not assumed:

* `service.sh` starts at boot (`/data/adb/tricky_store/integrity.log` records
  `service.sh start` → `pif service stage done` → `starting the TrickyStore daemon loop`),
  and the daemon loop runs: 11 `MainKt` launches in about two minutes, each one logging
  `Load /data/adb/modules/playintegrityfix/libtricky_store.so using system ns: ok` and then
  exiting 0.
* Nothing is injected: the target app's attestation stays genuine (see above), no
  `/data/adb/tricky_store/key_db` is ever created, and `keystore2` does not map the library.

Reading `/proc/<pid>/maps` cannot be used as evidence on this phone because
`CONFIG_KSU_SUSFS_SUS_MAP` hides mappings; the conclusion above comes from the functional
KeyAttestation result instead.

## What the ROM must not write

`resetprop -n -p` creates `/data/property/persistent_properties` without an explicit mode,
and under init's umask 0 the file lands at `0666`. init then refuses it —
`init: Could not load single persistent property file ... Skipping insecure file` — and
every persistent property is lost for that boot, including `persist.sys.usb.config=adb`, so
adbd never comes up on its own.

The module repairs this on every boot (`bin/fix-persist.sh`, called from
`post-fs-data.sh` after the Play Integrity Fork prop stage): it restores the file to
`0600` and re-arms `persist.sys.usb.config=adb`. `tests/run.sh` covers it with a negative
control (0666 in, 0600 out). Measured after the fix: a reboot with the phone untouched
brought `adb devices` back online 38 s after `adb reboot`, with no `keyguardGoingAway`
or Settings activity in logcat before it.

## Sustained BASIC, and the other invariants

The shipped configuration (`keybox_mode=auto`, so an existing keybox is kept and the bundled one is only
installed when there is none, `auto_keybox=0`, `ts_daemon=0`, target list of four packages,
`fix-persist.sh` active) produced, boot after boot,
`deviceRecognitionVerdict: ["MEETS_BASIC_INTEGRITY"]` with
`appRecognitionVerdict: PLAY_RECOGNIZED` and `appLicensingVerdict: LICENSED` — including three
consecutive boots on the earlier keybox configuration. `bin/boot-verdict.sh` now repeats that
measurement 60 s after every boot and appends the parsed result to
`/data/adb/tricky_store/verdicts.jsonl`, so each boot documents itself instead of relying on a
person to press a button; `bin/integrity.sh verdicts 5` prints the tail.

`bin/integrity.sh doctor` also checks the local hiding invariants that matter more than a verdict
here: SUSFS active, no `/system/bin/su` in the default namespace, `persistent_properties` at
`0600`, and `persist.sys.usb.config` still carrying `adb`.

`su_compat` was on (`ksud feature list` → `[ENABLED] su_compat (ID=0)`), which is why a 6.1 MB
`/system/bin/su` existed; `ksud feature set su_compat 0` removes it, and root over adb then goes
through adbd itself (`adb shell id` → `uid=0(root) ... context=u:r:ksu:s0`). With `su_compat` off,
`adb shell su -c ...` no longer exists, so every command in this document is meant to be run as
`adb shell <command>` on a root adbd.

## CPU cost of the keystore daemon

Tricky Store's daemon exits after a second or two on this ROM, and the upstream `service.sh` respawns it
every two seconds. Measured with `/proc/<loop pid>/stat` fields 16 and 17 over a 60.13 s window:
`19189 17319` → `20064 18152`, i.e. 1708 ticks = **0.284 core, continuously**, for a daemon that does
not modify the attestation here. `ts_daemon` is therefore `0` by default and the loop is not started;
with the loop stopped the same window measures **0 ticks**, and a verdict taken afterwards still returns
`MEETS_BASIC_INTEGRITY`. Setting `ts_daemon=1` starts the loop with a backoff that stops it after five
runs shorter than 10 s and writes that to `integrity.log`.

## How the verdict was read

```sh
adb shell sh /data/adb/modules/playintegrityfix/bin/integrity.sh verdict
```

That wakes the phone, resets Simple Play Integrity Checker, taps its request button and
prints the raw `System.out` JSON from logcat; `tools/measure-spic.sh` runs the same thing
from the host over adb.
