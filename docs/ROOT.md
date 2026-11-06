# Root tutorial — Meizu mBlu 21 (M416H), step by step

The unlock and the `init_boot` writes below were run on this phone from Fedora on 2026-11-02; the same download-mode tooling had already read every partition out of the phone from Windows, which is where the 44-file dump came from. Both hosts use the same `spd_dump` with the same arguments, and the page gives the command for each. What was measured, with the partition hashes, is in [HARDWARE-2026-11-02.md](HARDWARE-2026-11-02.md).

**What this does and does not touch.** Only `init_boot_a` is written. `boot`, `vendor_boot`, `dtbo` and `vbmeta` keep their Meizu content, which is the whole trick: this bootloader rejects any foreign `vbmeta` and any foreign `vendor_boot`, but it does not enforce verification of `init_boot`, so a root module loaded from that ramdisk boots fine.

**Cost.** Unlocking with the CVE-2022-38694 method sets a flag in `miscdata`; it does **not** wipe userdata. That was measured: after unlocking, `/data` still held 2.9 GB, 255 packages, and FBE was still active. Formatting is only needed if you later flash a different Android system.

---

## 0. Prepare the host

### Linux host

```sh
sudo dnf install -y android-tools openssl libusb1-devel gcc make
```

Download-mode USB (`1782:4d00`) needs a udev rule so `spd_dump` works without root:

```sh
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1782", ATTR{idProduct}=="4d00", TAG+="uaccess"' \
  | sudo tee /etc/udev/rules.d/51-unisoc-download.rules
sudo udevadm control --reload
```

Build the unlock and write tools from [TomKing062/CVE-2022-38694_unlock_bootloader](https://github.com/TomKing062/CVE-2022-38694_unlock_bootloader/releases): `spd_dump`, `gen_spl-unlock`, `chsize`. Keep them in one working directory, `~/mblu21-tools`, together with `fdl1-dl.bin`, `fdl2-dl.bin`, `fdl2-cboot.bin`, `misc-wipe.bin`, `spl-unlock.bin` and `custom_exec_no_verify_65015f08.bin` from the same release. Every `spd_dump` command below runs from that directory.

### Back up first (both hosts)

Two partitions decide whether you can undo everything: `init_boot_a` (what root replaces) and `boot_a`. Before root you have no `su`, so they come out through download mode:

```sh
cd ~/mblu21-tools
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec \
  r init_boot_a r boot_a r vendor_boot_a r vbmeta_a reset
```

That leaves `init_boot_a.bin` (8 388 608 B) and `boot_a.bin` (67 108 864 B) in the working directory. **Keep them.** They are the only reliable way back to stock.

### Windows host

Everything below works on Windows 10/11 with the same CVE-2022-38694 release, which ships `spd_dump.exe`, `gen_spl-unlock.exe` and `chsize.exe`.

1. **Install the Unisoc USB driver.** From the release, run `SPD_Driver_R4.20.4201/Win10/DPInst64.exe` (or `Win7`/`Win8` for those systems) and accept the driver prompt. Without it, Windows never binds the download-mode device and `spd_dump.exe` reports `find port failed` forever.
2. **Get the tools.** Extract the same `ums9230_universal_unlock_UFS` package into a short path such as `C:\mblu21\tools`; the tools write their dumps and the patched image into the current directory, so it has to be writable. That folder must contain `spd_dump.exe`, `gen_spl-unlock.exe`, `chsize.exe`, `fdl1-dl.bin`, `fdl2-dl.bin`, `fdl2-cboot.bin`, `misc-wipe.bin`, `spl-unlock.bin` and `custom_exec_no_verify_65015f08.bin`.
3. **Get adb.** Platform-tools from Google (`adb.exe`, `fastboot.exe`); only `adb` is needed for the checks and the manager install.
4. **Open a Command Prompt in that folder** (`cd /d C:\mblu21\tools`) and run the commands from this page without the `./` prefix: `spd_dump --wait 300 ...`.

The release also ships `unlock_autopatch_9230.bat`, which runs the whole unlock sequence with pauses. It is fine for the unlock step, but it is not the whole job: patching `init_boot_a` and writing it still needs the commands below.

The Windows tools need the phone in the same download mode (§1), and the same rule applies: after every `spd_dump.exe` run the phone leaves download mode, so re-enter it for the next write. `fastboot.exe flash` fails on this unit exactly as it does on Linux (`Status read failed`), so it is not used anywhere in this tutorial.


---

## 1. Enter download mode

This is the step people get wrong, so read it once:

1. Unplug USB and power the phone **off**.
2. Hold **Volume Up**.
3. Plug USB in while still holding it.
4. Keep holding for about ten seconds, then release. The screen stays black.

Check from the host:

```sh
lsusb | grep 1782     # must print 1782:4d00
```

On this unit **Volume Down only reached the charging screen**; Volume Up is the combination that reaches `1782:4d00`. If the phone boots Android instead, repeat from step 1. On Windows the check is **Device Manager > Ports**, where the phone must appear as `SPRD U2S Diag (COM<n>)`; an unknown device there means the Unisoc driver from the Windows host section is missing. Every `spd_dump` run drops the USB link when it finishes, so download mode is entered freshly for every write — that is normal, not a failure.

---

## 2. Unlock the bootloader

The ROM in the phone does not route through `fastboot flashing unlock`; the Unisoc BootROM is used instead (CVE-2022-38694). Run these from the tools directory, entering download mode before each line that opens a session.

The commands below are written for Linux. On Windows they are identical without the `./` prefix, and the supplied `unlock_autopatch_9230.bat` runs this whole section with pauses between the steps, so it is the easier route there.

Read the current SPL and U-Boot, and resign the SPL with the unlock patch:

```sh
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec r splloader r uboot e splloader e splloader_bak reset
./gen_spl-unlock splloader.bin
mv splloader.bin u-boot-spl-16k-sign.bin
./chsize uboot.bin
mv uboot.bin uboot_bak.bin
```

Boot the unlock payload through U-Boot:

```sh
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec w uboot fdl2-cboot.bin reset
sleep 10
./spd_dump exec_addr 0x65015f08 fdl spl-unlock.bin 0x65000800
```

Verify the flag, then restore the stock SPL and U-Boot and clear `misc`:

```sh
./spd_dump exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec \
    verbose 2 read_part miscdata 8192 64 m.bin reset
xxd m.bin | head
```

- 64 zero bytes → still locked. Run the `w uboot fdl2-cboot.bin` and `fdl spl-unlock.bin` lines again.
- A device string plus two hashes → unlocked.

```sh
./spd_dump exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec \
    r boot w splloader u-boot-spl-16k-sign.bin w uboot uboot_bak.bin w misc misc-wipe.bin reset
```

Power the phone on normally: it boots the stock Android 14 system, now with `ro.boot.flash.locked=0` and `verifiedbootstate=orange` ("LOCK FLAG IS: UNLOCK" on the splash).

**The unlock does not erase your data.** Measured on this phone: after unlocking, `/data` still held 2.9 GB, 255 packages were installed, and FBE was still active. The CVE-2022-38694 method only flips the flag in `miscdata`; it never runs the wipe that `fastboot flashing unlock` would. Formatting becomes necessary only when a different Android system is installed later.

---

## 3. Pick one root implementation

Both were booted on this phone; pick one, not both. They replace the same file (`init_boot_a`), so switching later is just flashing the other image.

| | SukiSU-Ultra 4.3.0 | KernelSU-Next 3.4.2 |
|---|---|---|
| Image | `init_boot-sukisu-ultra-lkm.img` | `init_boot-kernelsu-next-lkm.img` |
| SUSFS (root hiding) | yes, by installing the guard module (§6) | yes, by installing the guard module (§6) |
| Manager app | `SukiSU_v4.3.0_41100-release.apk` | `KernelSU_Next_v3.4.2_33355-release.apk` |
| Manager in the release | yes (`a928eb57…`) | yes (`774a5511…`) |
| Extra kernel extensions (KPM, CPU spoof) | yes (KPM also needs the KernelPatch `boot`, README "KPM boot") | no |

SukiSU-Ultra is the one this phone ended up running. Take the image from the release page (`mblu21-root-20261102`) and check it:

```sh
mkdir -p ~/mblu21-root && cd ~/mblu21-root
gh release download mblu21-root-20261102 -R tickernelz/android_kernel_meizu_mblu21
sha256sum -c SHA256SUMS
```

The two images are:

| File | sha256 |
|---|---|
| `init_boot-sukisu-ultra-lkm.img` | `cd060b9ede002187c4b90a9f76f16247f39ff78ec1995dad229465d0ede6a5fa` |
| `init_boot-kernelsu-next-lkm.img` | `3ed94999b93d60c2e01202ef78d7522dc42f045b766dd0de1bc6c83c07b92592` |

---

## 4. Write the image through download mode

`fastboot flash` does **not** work on this unit: it answers `Sending … OKAY` and then fails at `Writing` with `Status read failed (No such device)`. Every write goes through `spd_dump`.

Enter download mode (§1), then:

```sh
cd ~/mblu21-tools
D=~/mblu21-root
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec w init_boot_a $D/init_boot-sukisu-ultra-lkm.img reset
```

Windows, from the tools folder with the image copied next to the tools (`^` continues a line in `cmd.exe`):

```bat
spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 ^
    fdl fdl2-dl.bin 0x9efffe00 exec w init_boot_a init_boot-sukisu-ultra-lkm.img reset
```

Success looks like `Write Part Done` followed by `rc=0`. If the run ends with `LIBUSB_ERROR_IO` or `find port failed`, the phone left download mode before finishing: enter it again and rerun the same command. Nothing is half-written in that case — the partition keeps its previous content.

Only `init_boot_a` is written. If the phone ever boots from slot `_b`, write `init_boot_b` with the same image.

---

## 5. Boot and install the manager

Unplug, press Power, wait for Android to finish booting. Then:

```sh
adb install ~/mblu21-root/SukiSU_v4.3.0_41100-release.apk
```

On Windows use `adb.exe` with the folder you actually downloaded to, for example `adb install C:\mblu21\root\SukiSU_v4.3.0_41100-release.apk`. Every `adb shell` command in this tutorial works the same there as long as the single quotes are kept: `cmd.exe` passes them through, and the shell on the phone is what needs them.

Open the app once. It should show the kernel as `LKM`, the version as `Working`, and the manager version `v4.3.0`. Grant root to the apps you want.

### Prove root from the host

```sh
adb shell su -c 'id'
```

Expected:

```
uid=0(root) gid=0(root) ... context=u:r:ksu:s0
```

More checks:

```sh
adb shell su -c '/data/adb/ksud -V'        # ksud 4.3.0 (uapi: 6)
adb shell su -c 'getenforce'               # Enforcing
adb shell su -c 'uname -r'                 # 5.15.149-android13-8-00008-gbe074b05e5af-ab12096863
```

If `su` hangs, open the manager app: the first `su` call asks for permission and the prompt is on the phone screen, not in the terminal.

SELinux stays **Enforcing** with the LKM path — there is no reason to set permissive.

---

## 6. Root hiding for banking apps (SUSFS)

Root alone is detected by most banking apps. SUSFS hides the interesting parts: mount points, `/proc` entries, module list, kernel version, and the root driver's own symbols.

**Check first whether the kernel already carries SUSFS:**

```sh
adb shell su -c '/data/adb/ksud susfs implementation'
```

- `builtin`: SUSFS is in the kernel. Do not install the guard module. Of the `boot-<variant>.img` kernels only `boot-sukisu-ultra.img` and `boot-sukisu-ultra-kpm.img` are built this way (`CONFIG_KSU_SUSFS=y` in their `config-report.txt`); measured on this phone on 2026-11-06 with both, after re-signing: `builtin`, and no `susfs_guard_lkm` in `/proc/modules` (README [Status](../README.md#status)). If the module is installed on such a kernel, remove it with `ksud module uninstall susfs_guard_lkm` and reboot; that removal has not been verified after a reboot yet.
- Anything else (the LKM path of §3-§5, and `boot-kernelsu-next.img`, whose config has `CONFIG_KSU=y` without `CONFIG_KSU_SUSFS`): install the guard module below. `boot-bakasu.img` is built without the SUSFS patch, and whether the guard module works with its driver is not measured ([release-notes/bakasu.md](../release-notes/bakasu.md)).

The guard module is included in the same release as `susfs_guard_lkm-module.zip`:

```sh
adb push susfs_guard_lkm-module.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/susfs_guard_lkm-module.zip'
adb reboot
```

After the reboot:

```sh
adb shell su -c '/data/adb/ksud susfs implementation'   # lkm
adb shell su -c '/data/adb/ksud susfs version'          # v2.3.0
adb shell su -c '/data/adb/ksud susfs variant'          # GKI
adb shell su -c '/data/adb/ksud susfs status'           # true (SukiSU-Ultra only; KernelSU-Next has no status subcommand)
adb shell su -c 'cat /data/adb/ksu/log/susfs_guard.log'
```

The log must end with a line containing `rc=0 present=yes` for the boot that just happened.

```sh
adb shell su -c 'ksud susfs set-uname 5.15.149-android13-8-00008-gbe074b05e5af-ab12096863 "#1 SMP PREEMPT Tue Jul 16 15:36:08 UTC 2024"'
```

`set-uname` is the one check that proves the whole chain end to end: from a **non-root** shell, `uname -r` then reports the string you set. Put the stock pair back when you are done experimenting.

Two things SUSFS does not fix, so do not chase them in this repo:

- The manager app itself stays installed and visible. Hiding it is a manager-side feature.
- Play Integrity attestation still fails; apps that call the Integrity API need a PIF-style module.

---

## 7. Go back to stock

```sh
cd ~/mblu21-tools
./spd_dump --wait 300 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 \
    fdl fdl2-dl.bin 0x9efffe00 exec w init_boot_a ~/mblu21-backup/init_boot_a.bin reset
```

Windows: the same command with `spd_dump` instead of `./spd_dump` and `init_boot_a.bin` in the tools folder.

The same untouched images are in the stock firmware release [mblu21-stock-U01005-20261031](https://github.com/tickernelz/android_stock_meizu_mblu21/releases/tag/mblu21-stock-U01005-20261031) as `init_boot_a.bin` (`d07159a1…`) and `boot_a.bin` (`3a78e139…`). Boot once and check `adb shell su -c id` fails — that is the root gone. Userdata is untouched by this operation.

Leaving the bootloader unlocked does not by itself break apps; it only prints the orange warning on the splash screen.

---

## 8. Verify the whole install in one go

One host command proves root, the manager, SELinux and SUSFS:

```sh
adb shell su -c 'id; /data/adb/ksud -V; getenforce; /data/adb/ksud susfs implementation'
```

Expected: `uid=0(root) ... context=u:r:ksu:s0`, a `ksud` version, `Enforcing`, and `lkm` once the guard module from §6 is installed (`builtin` on `boot-sukisu-ultra` and `boot-sukisu-ultra-kpm`, without the module).

Compare the untouched partitions against the stock hashes; only `init_boot_a` may differ:

```sh
for p in boot_a vendor_boot_a vbmeta_a dtbo_a; do
  printf "%s " $p
  adb shell su -c "dd if=/dev/block/by-name/$p bs=1M 2>/dev/null | sha256sum"
done
```

On Windows run the same `adb shell` line once per partition and compare the hash by eye (`cmd.exe` has no `for` loop worth writing).

Stock values measured on the reference phone: `boot_a` `3a78e1394a5c3c52252384c7a136ae3c6c4fd758f0ba4a781c91813b1352f6da`, `vendor_boot_a` `c053086cefb9845e8b604224719f71d1b2503e46fee528ba1cd7864a9ea0ed29`, `vbmeta_a` `83789a72825563cc6fe6e93a5658f2f06a962e09c6f1884d46e15ffb7b7607aa`, `dtbo_a` `71e5cae7dfabc341e4d39d7f15dadb72aec8636e68a33654b99619532936874e`. A different value means something other than `init_boot_a` was written.

## 9. When something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `lsusb` never shows `1782:4d00` | wrong key or timing | power off, hold **Volume Up**, plug in, hold ten seconds |
| Windows: no `SPRD U2S Diag (COM<n>)` appears | Unisoc driver missing, or the port is an unknown device | install `SPD_Driver_R4.20.4201/Win10/DPInst64.exe`, replug |
| Windows: `spd_dump.exe` prints `find port failed` in a loop | phone not in download mode, or a path with spaces | re-enter download mode, move the tools to `C:\mblu21\tools` |
| `fastboot flash` ends with `Status read failed` | fastboot is read-only here | use `spd_dump` (§4) |
| `LIBUSB_ERROR_IO` mid-write | phone left download mode | re-enter download mode, rerun the same command |
| stuck on the Meizu logo | the image written to `init_boot_a` is bad, or `vbmeta`/`vendor_boot` was replaced | enter download mode, write stock `init_boot_a`, and stock `vbmeta_a`/`vendor_boot_a` if you changed them |
| boots, but no `su` | manager app not installed, or root not granted yet | install the manager (§5), open it, grant |
| `ksud` not found | the LKM image was never written, or the patched image was overwritten by a stock restore | reflash the patched `init_boot_a` |
| SUSFS not loaded after reboot | module missing or `ksud insmod` failed | run `ksud susfs implementation` first: `builtin` needs no module; otherwise `cat /data/adb/ksu/log/susfs_guard.log`, reinstall §6 |
| banking app still refuses | manager visible or Play Integrity failing | §6 notes: not covered here |

A phone that will not boot is not a brick: the BootROM is reachable on every power-up, so download mode plus a stock image always brings it back.

## 10. PixelOS 17 ROM: SukiSU-Ultra v4.3.0-r2 or KernelSU-Next v3.4.2

Sections 1-9 are for the stock Meizu ROM and its `v4.3.0` images. On the unofficial PixelOS 17 ROM ([pixelos_build_mblu21](https://github.com/tickernelz/pixelos_build_mblu21)) root uses the same LKM path, with both root implementations built from their release tags. That ROM ships the stock Meizu boot image, so the kernel is unchanged and has no KernelSU built in. Pick one implementation.

| | Stock ROM (§3) | PixelOS 17 build `20261105-1807` (release `mblu21-pixelos-root-20261106`) |
|---|---|---|
| SukiSU-Ultra | `v4.3.0` | `v4.3.0-r2` (`645ef986`): `init_boot-PixelOS_mblu21-17.0-20261105-1807-sukisu-v4.3.0-r2.img` (`da2cac6d…`), `SukiSU_v4.3.0-r2_41150-release.apk` |
| KernelSU-Next | `v3.4.2` | `v3.4.2` (`4c706b59`): `init_boot-PixelOS_mblu21-17.0-20261105-1807-kernelsu-next-v3.4.2.img` (`85da3c7d…`), `KernelSU_Next_v3.4.2_33355-release.apk` |
| SUSFS guard | `susfs_guard_lkm` `v2.3.0` | same `.ko` bytes (`024aa0de…`): the module zip for SukiSU-Ultra, built into `ksud` for KernelSU-Next |

A patched `init_boot` fits every ROM build whose stock `init_boot.img` has the same sha256. Builds `20261105-1507` and `20261105-1807` both have `738c8151…`, so the 1507 SukiSU image in `mblu21-pixelos-root-20261105` is the same file as the 1807 one. On the phone build 1807 shows as `PixelOS_mblu21-17.0-20261105-1800` (`ro.build.date.utc=1793901647`). For a build with a different stock `init_boot`, patch it with `patch-init-boot.sh` from the release; installing such a ROM update without a repatched `init_boot` drops root.

Install from a phone that is already rooted (commands in the release notes), or write the image to the active slot (`init_boot_a` or `init_boot_b`, see `getprop ro.boot.slot_suffix`) with `spd_dump` as in §4. `ksud`'s `resetprop -p`, called by PlayIntegrityFix on every boot, leaves `/data/property/persistent_properties` at `0666`, and `init` then drops every persisted property on the next boot (adb came up only after 194 s when this happened). Running `adb shell su -c 'chmod 600 /data/property/persistent_properties'` before a reboot is expected to avoid it (not tested); what was tested is the repair afterwards, `chmod 600` and then `setprop` of any `persist.` property, after which `init` rewrites the file as `0600`. Then check:

```sh
adb shell su -c '/data/adb/ksud -V'              # ksud 4.3.0-r2 (uapi: 6) | ksud 3.4.2 (uapi: 5)
adb shell su -c 'grep ^kernelsu /proc/modules'   # kernelsu ... Live
adb shell su -c '/data/adb/ksud susfs version'   # v2.3.0
adb shell su -c 'getenforce'                     # Enforcing
```

Those outputs were measured on the phone on 2026-11-06, one variant at a time, after installing from a rooted phone with `dd` (raw output: `verify-on-phone-20261106.txt` in the release). `sys.boot_completed` came 28.5 s after kernel start with SukiSU-Ultra and about 30.5 s with KernelSU-Next, one boot each; the two numbers are not comparable, because the SukiSU-Ultra boot ran with its persisted properties dropped. The `spd_dump` write of these images, a first install on an unrooted PixelOS phone, and `chmod 600` before a reboot were not tested.

---

## Related reading

- [HARDWARE-2026-11-02.md](HARDWARE-2026-11-02.md) — what the bootloader enforces, what was measured, live partition hashes.
- [../README.md](../README.md) — how the images are built, ABI gate, provenance.
- [android_device_meizu_mblu21-recovery](https://github.com/tickernelz/android_device_meizu_mblu21-recovery) — recovery images (note: `vendor_boot` is AVB-enforced on this phone, so recovery does not currently load).
