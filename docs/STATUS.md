# Galaxy Watch 4 (SM-R870): verified state

What has been verified on the watch and on the files. For the procedure see `SKILL.md`. For pitfalls see `docs/LESSONS.md`.

## Device and software

| Item | Value |
|---|---|
| Model | SM-R870 |
| Build | `BP2A.250325.020.R870XXS2JZG3` |
| Kernel | `5.15.180-33003255-abR870XXS2JZG3` |
| Bootloader | unlocked (`ro.boot.verifiedbootstate=orange`, `ro.boot.flash.locked=0`, `warranty_bit=1`) |
| Magisk | 31.1 (`magisk -v` → `31.1:MAGISK:R`), `magiskd` running from the boot image |
| Root for the ADB shell | yes: `su -c id` → `uid=0(root)`, context `u:r:magisk:s0` |

## Boot image

The Magisk-patched image is `magisk_patched-31100.img`, SHA-256 `b99c0f2e…`, MD5 `23739d590826bf85737826cba8d8234e`. The stock image (SHA-1 `839c3021a4b874910fb041d48fe2107742851499`) matches the boot digest in `vbmeta.img` from the firmware. The SHA-1 stored in `.backup/.magisk` of the Magisk image points to the same stock.

Vbmeta is **not** patched (`flags=0`). The watch boots anyway, most likely because the bootloader is unlocked. Not tested on a locked bootloader.

## Magisk app on this watch (observed)

- On a clean system the app shows "Requires additional setup" or "Not installed".
- Tapping OK on "Requires additional setup" reboots the watch.
- After the reboot, clearing the app data makes root work at once. The dialog does not come back.
- The Install page offers only "Patch firmware / image". There is no Direct install and no Superuser section in Settings.

## Current state of the watch (may change)

- Root for the ADB shell works.
- The font scale is set to 0.7. Restore with `settings put system font_scale 1.0`.
- `/data/local/tmp` has no chain files. The temporary files from UI debugging were removed.

## Artifacts (SHA-256)

Binaries and sources marked "this repository" are in the repo. The two boot images and the Magisk APK are not.

| Artifact | SHA-256 | Source |
|---|---|---|
| Magisk-patched boot image (`magisk_patched-31100.img`) | `b99c0f2ea7a929a12c8f8f69bb6f326bef74ac6c0f56435950e2131d5a915f58` | not in this repository; made on the watch with Magisk 31.1 from the stock `boot.img` |
| Stock boot image (`boot.img`) | `026bf467bfba1634ee552939abe5a4067966afa22d3a59085e89fa57059e9828` | not in this repository; `boot.img` from the `R870XXS2JZG3` firmware package |
| Magisk APK 31.1 | `89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7` | not in this repository; <https://github.com/topjohnwu/Magisk/releases> |
| adbkeeper APK (`apk/gw4-adb-keeper.apk`) | `9f8f75b3610a97b9e233cd7fd03b4115282786cf0b29319b731f9ec7de0a6303` | this repository |
| KO module (`bin/dfroot_w4.ko`) | `83363c20dd9fbc42f4db327aafe031372e7b3ae2c16f0f801e77e517ce4c9078` | this repository, built from `src/dfroot_w4.c` |
| Bootstrap (`bin/dfroot_bootstrap`) | `a7706f3d18c8eb3c6035fbb66bd48892416cba7db3365680f91bfc2ed1f51333` | this repository, `src/dfroot_bootstrap` |
| Shellcode v6 (`bin/df_shellcode.bin`) | `b8000b057c61177813697a14ead82e1c919aa56fe38859bc3620effafbc0f222` | this repository, built from `src/shellcode_v6.S` |
| classes.dex (`bin/classes.dex`) | `91b2a0dd3d76a4e6c41f4c7c9be9ec4c16ee66c16d01531bde48f66d105f6246` | this repository, built from `src/DirtyFragSetup.java` |
| Exploit (`bin/dirtyfrag_exploit`, diagnostic build) | `59138b56e5f5930907c174063e5a0f7ba2b664b96790c7b013cb7b71ca8ec200` | this repository, built from `src/dirtyfrag_exploit.c` |
| Splicehelper (`bin/splicehelper`) | `e32db45008c9bdf6e0b753e6f81d2cee8befc6b4cf44a4d380e6f363d16d2893` | this repository, `src/splicehelper.c` |

## Sources

- Magisk: <https://github.com/topjohnwu/Magisk> (version 31.1).
