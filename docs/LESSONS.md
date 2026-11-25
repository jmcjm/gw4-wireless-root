# Lessons: what worked and what to avoid

Things learned while building and testing the chain. Procedure: `SKILL.md`. Verified state and artifact hashes: `docs/STATUS.md`. Warnings for users: `README.md`.

## What worked (verified)

- The Magisk-patched boot image (`magisk_patched-31100.img`) is in the boot partition (hash checked) and boots. `magiskd` runs from the ramdisk.
- The DirtyFrag chain reached the boot write: hook fired, bootstrap started, `dd` finished, marker `/dev/dfm6`.
- The SELinux domain transition works via `execve` into `/vendor/bin/insmod`. Writing the context to `/proc/self/attr/exec` alone does not change the domain. The context applies on the next `execve`.
- The `/dev/df` mutex needs plain `O_CREAT|O_EXCL`. Removing the file before opening disables the lock.
- After the Magisk app's initial setup and a reboot, clearing its data gave root to the ADB shell at once.
- On SM-R860 (kernel 4.19.151) the Magisk patch runs from the ADB shell with `boot_patch.sh` and the binaries from the APK (`BOOTMODE=false`). It produced `magisk_patched-R860.img` (SHA-256 `5fbc4fdd…`) from the firmware `boot.img` (`6583e3a0…`) without a tap on the watch. It was not flashed.

## Pitfalls

- `unlink("/dev/df")` before `O_EXCL` in the shellcode: the mutex does not block the next run.
- `init_module` called from the init domain fails the `module_load` policy. The permission exists only for `rootfs`. Use `execve` of insmod instead. The v5 shellcode used `init_module` and failed.
- A short `splice` midway through the KO write (e.g. at block 15) aborts the exploit. The patches stay in the page cache and disappear only after a reboot. Restoring `libbinderdebug.so` may fail.
- The kernel module ends with `-ENODEV` after the bootstrap has run, so it disappears from `/proc/modules`. The bootstrap still runs. The `insmod` exit code is odd.
- `dmesg` and `/proc/kmsg` are blocked for the ADB shell. Kernel diagnostics need the bootstrap, running as root, to write logs.
- The `/data` partition may be damaged before the boot write. The `fs_mgr_mount_all` error was visible on the watch screen before the write. A factory reset removed it.
- After a reboot the system has a high load (ART optimization, `kswapd`). SA processes can sit in state D. Wait for the load to drop before running the exploit.
- Screenshots and `uiautomator dump` leave files on the watch. Delete them after use.
- On SM-R860 the Samsung RKP hexpatch in `boot_patch.sh` does not match the 4.19.151 kernel and prints `Failed to patch`. The next hexpatch (defex) does match. The patch run still ends with exit 0, so the failure is only visible in the log.

## Unresolved

- The cause of the bootloop after the first start with the Magisk image. A damaged `/data` partition is suspected, but without logs this cannot be confirmed.
- The cause of the odd `insmod` exit code, and whether the `-ENODEV` return is intentional. The code has no comment about the intent.
- Whether every future run must write the boot partition. `dfroot_bootstrap` does it without a backup.
- The mechanism by which the Magisk app's initial setup and data clearing give root.
- The behavior on a locked bootloader. Not tested.
- SM-R860 (kernel 4.19.151, `CONFIG_UH=y`, `CONFIG_RKP=y`, `CONFIG_KDP=y`): the RKP hexpatch does not match, so RKP stays enabled in the patched kernel. Whether `dfroot_w4.ko` loads and whether the chain works with RKP and UH active is not known. The validated R870 JZG3 kernel has the same UH, RKP and KDP options enabled, so their presence alone does not explain a failure.
