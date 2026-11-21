---
name: gw4-root
description: Use when restoring root on a Galaxy Watch 4 SM-R870 after a clean system install — firmware download, boot.img extraction, Magisk patching, the DirtyFrag v6 exploit chain, factory reset and Magisk setup. Also for debugging exploit, marker, bootstrap and SELinux problems on the watch.
---

# Root Galaxy Watch 4 (SM-R870)

Procedure for restoring root after a clean system. Does not flash `boot.img` via NetOdin/Brokkr (Wi-Fi): SVB rejects unsigned boot images. Does not suggest Odin or download mode (project rule). Reference firmware: `R870XXS2JZG3`, kernel `5.15.180`, Magisk 31.1.

Repo with binaries, sources and documentation: this repository (GitHub: `jmcjm/galaxy-watch4-root`, private).

Requirements: bootloader unlocked (`orange`, `flash.locked=0`), `adb` on the same Wi-Fi network as the watch, the repo cloned locally. The full list is in `README.md`.

## Step-by-step procedure

### 0. Firmware and boot.img

Download the SM-R870 firmware from samfw.com (region XEO, version `R870XXS2JZG3`).

```sh
tar -xf AP_R870XXS2JZG3_*.tar.md5 boot.img.lz4
lz4 -d boot.img.lz4 boot.img
# SHA-256 stock: 026bf467bfba1634ee552939abe5a4067966afa22d3a59085e89fa57059e9828
```

### 1. Patching with Magisk on the watch

Magisk patches the file without root.

```sh
adb push boot.img /sdcard/Download/boot.img
adb install apk/Magisk-v31.1.apk
```

On the watch: Magisk → Install → Patch firmware / image → `boot.img`.

```sh
adb pull /sdcard/Download/magisk_patched-*.img magisk-boot.img
adb push magisk-boot.img /data/local/tmp/magisk-boot.img
```

A saved `magisk-boot.img` from the same firmware version can be reused.

### 2. Uploading the exploit chain

```sh
# run from the repository root
adb push bin/dirtyfrag_exploit /data/local/tmp/
adb push bin/df_shellcode.bin  /data/local/tmp/
adb push bin/dfroot_w4.ko      /data/local/tmp/dfroot.ko
adb push bin/dfroot_bootstrap  /data/local/tmp/
adb push bin/classes.dex       /data/local/tmp/
adb push bin/splicehelper      /data/local/tmp/
adb shell chmod 755 /data/local/tmp/dirtyfrag_exploit /data/local/tmp/dfroot_bootstrap /data/local/tmp/splicehelper
```

### 3. Exploit

Two terminals. The SA setup must keep running for the whole duration of the exploit (5 minutes).

**Terminal 1 — SA setup:**
```sh
adb shell "CLASSPATH=/data/local/tmp/classes.dex exec app_process /system/bin DirtyFragSetup"
# Wait for: "OK encap=..."
```

**Terminal 2 — exploit** (within 5 minutes of OK):
```sh
adb shell /data/local/tmp/dirtyfrag_exploit
```

Success: `hook fired` → `bootstrap started` → `*** SUCCESS: boot.img flashed! ***`

No markers or a hang → reboot and start again from step 3 (a reboot clears `/dev`).

### 4. Factory reset

The watch may bootloop after the first start with the Magisk image (cause not established, probably the `/data` state). Factory reset (wipe data). The watch then boots with our boot image and a clean `/data`.

### 5. Configuration

```sh
adb mdns services          # port changes after reboot
adb pair IP:PORT CODE
adb connect IP:PORT
adb install apk/Magisk-v31.1.apk
# Optional:
adb install apk/gw4-adb-keeper.apk
adb shell pm grant com.gw4root.adbkeeper android.permission.WRITE_SECURE_SETTINGS
```

### 6. Magisk initial setup → root

On the watch, open the Magisk app first. If it shows "Requires additional setup", tap **OK**. The watch reboots. After the reboot, clear the app data (**Settings → Apps → Magisk → Clear data**) and open the app again. Root works at once, and the dialog does not come back.

Then check root:

```sh
adb shell su -c id
# uid=0(root) gid=0(root) groups=0(root) context=u:r:magisk:s0
```

## How the exploit chain works

| Component | What it does |
|---|---|
| `DirtyFragSetup.java` | Opens an IPSec SA with AES-256-CBC, writes the parameters to `df_params`, keeps the transform alive for 5 min |
| `dirtyfrag_exploit.c` | Reads the SA parameters; patches `crash_dump32` in the page cache (replaced with `splicehelper`); writes the KO into the page cache of `libbinderdebug.so` through the bridge; injects the shellcode into the tail slack of `libc++.so`; places a trampoline on `sentry::sentry`; triggers the hook via an orphan; waits for markers; restores the originals |
| `shellcode_v6.S` (ARM32 Thumb-2) | uid==0 && tid==1 guard; mutex `/dev/df` (O_CREAT\|O_EXCL, no unlink); fork worker→grandchild; the grandchild writes `u:r:vendor_modprobe:s0` to `/proc/self/attr/exec` and execve's `/vendor/bin/insmod` with the KO |
| `dfroot_w4.ko` (ARM64 LKM) | Resolves `kallsyms_lookup_name` via kprobe; patches `avc_has_perm` and `avc_has_perm_noaudit` → return 0 (SELinux off); patches `task_defex_enforce` and `task_defex_user_exec` → return 0 (DEFEX off); invalidates the page cache of `crash_dump32`; starts the bootstrap via `call_usermodehelper` |
| `dfroot_bootstrap` | `dd magisk-boot.img` onto `/dev/block/by-name/boot`; marker `/dev/dfm6` = success |
| `splicehelper.c` | ARM32 no-libc binary; reads 16 B from the vendor file (read mode) or splices 16 B into a pipe (splice mode); runs in the `crash_dump` domain |

## Diagnostic markers

| Marker | Meaning |
|---|---|
| `/dev/df` | Shellcode hook fired (mutex) |
| `/dev/dxw` | Shellcode worker started |
| `/dev/dxs` | Grandchild finished (wait4 returned the status) |
| `/dev/dxb0`..`dxb3` | Bits of the insmod exit code |
| `/dev/dfm0` | KO bootstrap started (UMH) |
| `/dev/dfm1` | Bootstrap script started |
| `/dev/dfm6` | dd finished successfully |
| `/dev/dfm_nosrc` | `magisk-boot.img` missing |
| `/dev/dfm_ddfail` | dd returned an error |

## Pitfalls and open questions

All known pitfalls, the open questions and the reasoning behind them are in `docs/LESSONS.md`.

## Rebuilding

Instructions in `docs/BUILDING.md`.

## Documentation

- `docs/LESSONS.md`: what worked, pitfalls, unresolved questions, where the full knowledge lives
- `docs/STATUS.md`: verified state, versions and artifact hashes
- `docs/BUILDING.md`: rebuilding from source
