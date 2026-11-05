# Play Integrity on the mBlu 21

Every number below was measured on this phone, Meizu mBlu 21 (M416H), Android 17
(API 37) build `CP2A.260605.016`, bootloader unlocked, SukiSU-Ultra 4.3.0-r2 (LKM),
SUSFS guard v2.3.0-gki, NeoZygisk v2.4. The verdict comes from Simple Play Integrity
Checker reading the raw token from Play, not from a summary screen.

## Result

| Configuration | Keybox in use | Keystore interposer | Device verdict |
|---|---|---|---|
| Before any work: combined third-party drop-in (`AlwaysStrong [Inject]` v1.0.5) | `evokerrkey44.xml`, ecdsa only | TEESimulator | `MEETS_BASIC_INTEGRITY` |
| `mblu21-integrity` v1.0.0, `keybox_mode=existing` | `evokerrkey44.xml`, ecdsa only | Tricky Store 1.4.1 | `MEETS_BASIC_INTEGRITY` on 3 consecutive boots |
| `mblu21-integrity` v1.0.0, `keybox_mode=software` | Tricky Store's software keybox, ecdsa + rsa | Tricky Store 1.4.1 | `MEETS_BASIC_INTEGRITY` on 2 consecutive boots |
| `AlwaysStrong` restored as a cross-check | Tricky Store's software keybox, ecdsa + rsa | TEESimulator | `UNEVALUATED` twice |
| `mblu21-integrity` v1.0.0, `keybox_mode=software`, shipped state | Tricky Store's software keybox, ecdsa + rsa | Tricky Store 1.4.1 | `MEETS_BASIC_INTEGRITY` |

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

## How the verdict was read

```sh
adb shell su -c 'sh /data/adb/modules/playintegrityfix/bin/integrity.sh verdict'
```

That wakes the phone, resets Simple Play Integrity Checker, taps its request button and
prints the raw `System.out` JSON from logcat; `tools/measure-spic.sh` runs the same thing
from the host over adb.
