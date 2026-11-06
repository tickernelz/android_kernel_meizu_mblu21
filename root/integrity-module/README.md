# mblu21 integrity module

One KernelSU/Magisk zip for Play Integrity on the Meizu mBlu 21 (M416H): Play Integrity
Fork v19 supplies the certified fingerprint and prop cleanup, TEESimulator v4.0 runs AOSP's
reference KeyMint inside the real `keystore2` and re-signs attestation from the keybox, and
this module owns the target list, the security patch level and the keybox policy. It
replaces the combined third-party drop-in that occupied `/data/adb/tricky_store` and fetched
a keybox over plain HTTP at boot.

| File | Purpose |
|---|---|
| `module/module.prop` | module identity: id `playintegrityfix`, version `v1.0.0` |
| `module/customize.sh` | installer: moves the old `/data/adb/modules/tricky_store` aside, keeps the keybox already on the phone, seeds the config |
| `module/post-fs-data.sh`, `module/service.sh` | source the unmodified upstream PIF scripts, then hand the certificate provider to `bin/ts-daemon.sh` |
| `module/teesim/` | the pinned TEESimulator payload (`daemon`, `classes.dex`, `arm64-v8a/`), started from `module/service.sh`; its `sepolicy.rule` is merged into the module root at build time with comment lines stripped |
| `module/bin/webui.sh`, `module/webroot/` | WebUI: provider and keystore state, active keybox (sha256, algorithms, chain, age, source), last verdict, and a refresh button |
| `module/bin/integrity.sh` | `status`, `doctor`, `verdict`, `keybox`, `targets`, `sp` |
| `module/bin/keybox.sh` | keybox completeness report, the install-mode switch, timestamped backups under `backup/`, the `keybox.log` trail and the TEESimulator mirror |
| `module/bin/keybox-fetch.sh` | scheduled fetch, validation gate, backup, rollback, one log line per attempt |
| `module/bin/keybox-validate.sh` | keybox validator: XML shape, ecdsa+rsa, certificate chain linkage on the DER names |
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

## Certificate provider

The keybox is only useful when a process reads it and answers keystore attestation with it.
Upstream Tricky Store splits that in two: `libtricky_store.so` hooks the keystore call, and
`daemon` runs `app_process` with `service.apk` to build the certificate chain from
`/data/adb/tricky_store/keybox.xml`. The native library carries no PEM or keybox code of its own
(`strings libtricky_store.so` finds neither `/data/adb` nor `keybox`), so without the daemon
there is no chain to serve. `v1.1.0` shipped `ts_daemon=0` and stopped the loop after five runs
shorter than ten seconds, which left every boot without a provider.

`bin/ts-daemon.sh` replaces that: `ts_daemon=1` by default, it waits for `sys.boot_completed`
and for `keystore2`, starts `./daemon` from the module root, and restarts it with a backoff of
5 s doubling to 60 s. It never gives up on its own, and it logs `started pid=`, `exited rc=` and
`restarting in` lines to `/data/adb/tricky_store/integrity.log`.

`doctor` prints the provider state: the supervisor pid, the daemon pid, whether
`libtricky_store.so` is mapped into it, the number of launches in this boot, and the last start
and exit lines. A TEESimulator module, when the owner installs one, is reported as the active
provider instead, and `keybox_sync_teesim` mirrors the active keybox to
`/data/adb/teesim/keybox.xml`.

## Keybox contract

`bin/keybox-validate.sh` is the only gate. `doctor`, the fetch loop and `keybox_install` all use
it, and strict mode rejects an ecdsa-only file with `invalid incomplete: no rsa`; the diagnostic
`--structural` mode still accepts the shape but prints `incomplete: no rsa` so the state is
never silent. Play asks for an ecdsa and an rsa attestation record separately, so a keybox with
one algorithm can never serve both.

Every install writes to `/data/adb/tricky_store/keybox.log`, keeps the previous file under
`/data/adb/tricky_store/backup/keybox-<timestamp>.xml`, and prints the sha256 of what it wrote.
The file itself never leaves the phone and is never committed.

## Provenance

Two layers, one zip.

| Layer | Origin | Contents |
|---|---|---|
| base module | ZHA-4962, `main` `5c3e9e4` (Raka) | TrickyStore + Play Integrity Fork payload, target list, security-patch alignment, `fix-persist.sh`, `su_compat` off, SUSFS wiring, per-boot verdict recording |
| keybox fetch | ZHA-4968 (Yanto) | `bin/keybox-fetch.sh`, `bin/keybox-validate.sh`, `bin/keybox-cert-names.awk`, `bin/keybox-split.awk`, and the `keybox_url`/`keybox_file`/`keybox_fetch_interval_h` keys they read |

The RE evidence for why the fetch layer exists at all — and why a complete keybox is the only
remaining path to `MEETS_DEVICE_INTEGRITY` on this phone — is the `re-attestation` document on
ZHA-4968. Neither layer ships a keybox.

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
| `software` | install the software keybox that ships inside the Tricky Store release, but only when the content actually differs, backing up the previous file next to it |

The bundled software keybox is `software-keybox.xml` in the module and inside the official
Tricky Store zip (`DeviceID="sw"`); it carries both an `ecdsa` and an `rsa` key, which is
what Play asks for. It is a self-signed test chain, not a Google-signed one.

The module never downloads a keybox by default: `auto_keybox=0` and no source is
configured. Turning it on is an explicit decision. `bin/keybox-fetch.sh` is the engine:

| setting | meaning |
|---|---|
| `auto_keybox` | `1` runs the scheduled fetch; `0` keeps the engine silent |
| `keybox_url` | `https://` or `file://` source; plain `http://` and every other scheme are refused with a log line |
| `keybox_file` | local path used when `keybox_url` is empty |
| `keybox_fetch_interval_h` | minimum hours between attempts, default `24`; `service.sh` ticks every 15 minutes and skips anything not due |
| `keybox_sha256` | optional pin; a mismatch rejects the download |

A download is data only: the engine never executes what it fetches, and it validates
before it installs (`bin/keybox-validate.sh`):

* the root element is `AndroidAttestation`, the file is between 512 B and 64 KiB, and it
  carries no `DOCTYPE`, `ENTITY` or `script`;
* at least one `ecdsa` key and one `rsa` key, which is what Play asks for;
* every key has a private key and a certificate chain of at least two certificates whose
  declared `NumberOfCertificates` matches the file;
* each certificate's issuer matches the next certificate's subject, and the last
  certificate is self-signed, checked on the DER of both names.

The last rule is the one that catches a half-served or spliced file. A rejected download
never touches the keybox in use: the engine keeps `keybox.xml`, and when that file is
itself unusable it restores `keybox.prev.xml` (`bin/keybox-fetch.sh heal`).

Transport rules: `curl` runs with `--proto '=https' --proto-redir '=https'`, so a 302 to
plain http is refused. When `curl` is absent the busybox `wget` fallback is only used with
`keybox_sha256` set, because that wget build reports `TLS certificate validation not
implemented`; without the pin the fetch is refused with a log line instead of trusting the
connection.

Scratch space comes from the first writable candidate: `INTEGRITY_SCRATCH`, then
`$INTEGRITY_ROOT/data/adb/tricky_store` (that is `/data/adb/tricky_store`, root-owned, when
`INTEGRITY_ROOT` is unset), then `TMPDIR`, `/data/local/tmp`, and finally the directory of the
file being validated. Each candidate is probed with a real `mkdir`, and a trap removes the
scratch tree on exit and on `INT`/`TERM`/`HUP`. Nothing depends on `/tmp`, which a boot-time
module context does not have.

`heal` runs only when `auto_keybox=1` **and** a source is configured **and** `keybox.xml`
exists, so the default configuration never rewrites the owner keybox at boot.

Every attempt writes exactly one log line with the result and the reason; the replaced
file becomes `keybox.prev.xml`, and `keybox.source` records the source, the timestamp and
the sha256. The state file is rewritten whole, so a source containing `|`, `&` or a
backslash cannot corrupt it. Neither the log nor the stamp ever contains key material:

    keybox fetch rejected: invalid no-rsa
    keybox installed from file:///data/local/tmp/kb.xml sha256=… valid size=5843 keys=2 certs=4 ec=1 rsa=1
    keybox fetch refused: http://example.invalid/kb.xml is plain http; https:// or file:// is required

`bin/keybox-fetch.sh status` prints the schedule state, the installed source stamp and the
validation verdict of both `keybox.xml` and `keybox.prev.xml`.

A keybox carries another device's private attestation keys, which is why no keybox is
vendored here, why the shipped config names no source, and why the tests build their own
self-signed chains instead of using one.

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
