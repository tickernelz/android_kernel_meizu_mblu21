# What the mBlu 21 bootloader verifies (2026-11-02)

Every custom image we flashed on this phone died at the Meizu logo until one rule was
met. This page records the rule and the evidence, so nobody repeats the experiment.

## The rule

A `vendor_boot` / `init_boot` may carry any ramdisk, but the AVB blob stored in the
image has to stay the stock Meizu one. The bootloader compares the vbmeta public key
with the chain key recorded in the stock slot `vbmeta`. A test-key blob is rejected,
and so is a rebuilt `vbmeta` with verification disabled.

| Partition | Verified by the bootloader? | What works |
|---|---|---|
| `init_boot` | content not hashed, but the embedded blob must stay Meizu | root: Linux kernel module patched into the ramdisk (KernelSU-Next, SukiSU Ultra) |
| `vendor_boot` | same | custom recovery ramdisk: Lineage Recovery booted, OrangeFox/SHRP need their own init checks |
| `boot` | chained in `vbmeta` | do not touch; the stock GKI kernel is what boots |
| `vbmeta` | signature must be Meizu | never replace it |

## Evidence

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
