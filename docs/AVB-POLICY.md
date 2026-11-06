# What the mBlu 21 bootloader verifies (2026-11-02, corrected 2026-11-06)

The 2026-11-02 rule below said that every chained image must keep a Meizu-signed AVB blob.
The 2026-11-06 measurements disprove it for `boot`, `init_boot` and `vendor_boot`: with the
bootloader unlocked, a verification error on a chained partition is logged and ignored. Only the
top-level `vbmeta` still has to stay stock.

## The rule

| Partition | Verified by the bootloader? | What works |
|---|---|---|
| `vbmeta` | signature must be Meizu | never replace it |
| `boot` | chained in `vbmeta`, error allowed while unlocked | any kernel signed with our own key: stock kernel re-signed with `verity` (RSA-2048, `3d1b7985…`) and stock kernel plus KernelPatch both boot |
| `init_boot` | chained, error allowed while unlocked | root: Linux kernel module patched into the ramdisk (KernelSU-Next, SukiSU Ultra) |
| `vendor_boot` | chained, error allowed while unlocked | custom recovery ramdisk (Lineage Recovery, OrangeFox) |

## Bootloader log (`uboot_log` partition, 2026-11-06)

```
partion init_boot, verify_ret:0x5
read_lock_flag: s_switch_enable = 0, s_rpmb_key_status = 1
avb allow verification error in UNLOCK status while normal booting.
allow_verification_error is 1
init_boot_a: Public key used to sign data does not match key in chain partition descriptor.
vendor_boot_a: Public key used to sign data does not match key in chain partition descriptor.
```

The boot continues to `jump to kernel`. Earlier boots in the same log, taken while the phone was
locked, read `allow_verification_error is 0` and `avb_slot_verify() not allow verification error`.

Measured on the phone (`ro.boot.slot_suffix=_a`, `/proc/bootconfig` `verifiedbootstate = "orange"`):

| `boot_a` | sha256 | Result |
|---|---|---|
| stock, Meizu RSA-4096 `d46eb3be…` | `3a78e139…` | boots |
| stock kernel, re-signed RSA-2048 with `keys/` `verity` (`3d1b7985…`) | `9801ab94…` | boots, root `u:r:ksu:s0`, Enforcing |
| stock kernel + KernelPatch 0.14.0 (`scripts/patch_kpm.sh`), same key | `9910bfd8…` | boots in 48 s, `ksud extension list` shows `[AVAILABLE] kpm` |
| GKI kernel built from `be074b05` (stock `gki_defconfig`) + KernelPatch, same key | `c68132ad…` | boots in 48 s on two reboots, `[AVAILABLE] kpm`, 180 modules loaded |
| SukiSU-Ultra kernel from `feat/sukisu-kpm`, `patch_linux` 0.14.0 | `61d6e77d…` | stops at the logo (2026-11-03); cause below |

## Why the 2026-11-03 image hung

The `patch_linux` 0.14.0 binary from `SukiSU_KernelPatch_patch` rewrites the Image entry branch and
the `image_size` field but appends only 0x690 bytes: the 294,384-byte `kpimg` payload is missing, and
`kptools-linux -l` reports the result as `patched=false`. The first instruction then jumps into the
missing payload, before any console or pstore exists. Under QEMU (`-M virt -cpu cortex-a76`) the stock
Image reaches `/init`, the `patch_linux` output prints nothing at all, and the same stock Image patched
with `kptools-linux -p -k kpimg` (+0x48470 bytes, `patched=true`) prints the KernelPatch banner and
reaches `/init`. `scripts/patch_kpm.sh` uses `kptools-linux` with the pinned `kpimg` and refuses an
output that is not larger by the payload size or that `kptools` does not list as patched.

## 2026-11-02 evidence (vendor_boot, superseded)

- Stock `vendor_boot_a` embeds vbmeta `06daaf6e...` with public key `4fce36c7...`, which
  is exactly the chain key the stock `vbmeta_a` records for `vendor_boot`.
- SHRP r19 and OrangeFox r19 embed a test key (`2597c218...`) and rollback index 0; both
  stopped at the logo. So did `vbmeta` rebuilt with flags 3, unsigned and RSA-4096 signed.
- SHRP rebuilt with the stock blob inside (`12a0756a...`) booted to Android instead of
  hanging, which isolates the blob as the blocker.
- Lineage Recovery rebuilt the same way (`3f2ff23f...`, then `f484cb03...` with the
  backlight fix) reached recovery: `ro.boot.bootreason=recovery`, and recovery cleared
  the boot-control block itself.
- The root images (SukiSU Ultra 4.3.0, KernelSU-Next 3.4.2) keep the stock blob and boot
  with a ramdisk that no longer matches the recorded digest, confirming the content hash
  is not enforced on these partitions.

## Rebuilding an image with the stock blob

`tools/reseal_stock_avb.py` in `android_device_meizu_mblu21-recovery` swaps the blob and
keeps the ramdisk, DTB, cmdline and bootconfig. The reference blob is
`prebuilt/vendor_boot.avb.vbmeta` (`06daaf6e...`), taken from the stock dump.

## Two traps on this phone

- `fastboot flash` and `fastboot boot` answer `Status read failed`; write with `spd_dump`
  in Unisoc download mode or with `dd` as root.
- The bootloader uses **Volume Down** as its confirm key on the unlock warning screen.
  Pressing the physical Volume Down key inside recovery resets the phone (bootcause
  `Reboot due to sysdump finish`). Measured 2026-11-03: it happens without any root
  module in `init_boot`, with `sprd_pmic_wdt` loaded, and not for Volume Up or for a
  Volume Down event injected with `sendevent`, so it is below the recovery UI. Navigate
  with Volume Up (the menu wraps) and Power, or drive recovery over adb.
- recovery must set `/sys/class/backlight/sprd_backlight/brightness`; without it the
  screen is dark even though recovery is running.
