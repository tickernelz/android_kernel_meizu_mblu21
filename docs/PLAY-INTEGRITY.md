# Play Integrity on the mBlu 21 (LineageOS 24.0)

Measured on one Meizu mBlu 21 (M416H) on 2026-11-03, running a local LineageOS 24.0 build with device tree `0d92969` (SELinux enforcing).

| Setup | Device verdict |
|---|---|
| SukiSU-Ultra root and the modules below with their default settings | NO_INTEGRITY |
| The same, with the attestation setup used on the test phone | **MEETS_DEVICE_INTEGRITY**, also after a reboot |

MEETS_STRONG_INTEGRITY was not reached. The DEVICE verdict depends on attestation material this project does not ship, document or support, and it can stop working at any time. Nothing in the ROM, the kernel or the root images here changes the verdict on its own.

## What was installed

| Piece | Version |
|---|---|
| SukiSU Ultra | 4.3.0 (LKM in `init_boot`) |
| SUSFS guard | v2.3.0-gki (`susfs_guard_lkm.ko`) |
| NeoZygisk | v2.4 |
| Tricky Store | 1.4.1 (245-72b2e84) |
| Play Integrity Fix [INJECT] | v4.9-inject-s |

## How the verdict was read

```bash
adb shell am force-stop com.henrikherzig.playintegritychecker
adb shell am start -n com.henrikherzig.playintegritychecker/.MainActivity
adb shell input tap 383 594        # "Make Play Integrity Request"
adb logcat -d | grep System.out    # prints the raw verdict JSON
```

With the DEVICE verdict the raw JSON carries `deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"]`, `appRecognitionVerdict` `PLAY_RECOGNIZED`, `appLicensingVerdict` `LICENSED` and `playProtectVerdict` `NO_ISSUES`.
