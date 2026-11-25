# Rebuilding from source

A rebuild is only needed after a firmware version change (new kernel = new struct module layout, new symbol CRCs). With the same firmware version, the binaries in `bin/` work.

## Environment

Set these variables first, pointing them at your own installations:

```sh
export ANDROID_SDK=/path/to/android-sdk            # SDK root, with platforms/ and build-tools/
export NDK_HOME=/path/to/android-ndk-r29           # Android NDK r29
export KERNEL_TC=/path/to/clang-toolchain/bin      # clang toolchain for the arm64 kernel module
export KDIR=/path/to/kernel-5.15.180               # kernel source tree for the firmware version
```

What each one needs:

- `ANDROID_SDK`: platform `android-34` (for `android.jar`) and build-tools `35.0.0` (for `d8`).
- `NDK_HOME`: NDK r29 (for the ARM32 clang).
- `KERNEL_TC`: the clang toolchain used to build the kernel (AOSP clang r450784e).
- `KDIR`: the kernel source tree for the firmware, with `autoconf.h` as described below.

## classes.dex (DirtyFragSetup)

```sh
ANDROID_JAR="$ANDROID_SDK/platforms/android-34/android.jar"
D8="$ANDROID_SDK/build-tools/35.0.0/d8"

javac --release 11 -classpath "$ANDROID_JAR" src/DirtyFragSetup.java
"$D8" --min-api 28 --output bin/ DirtyFragSetup.class
rm -f DirtyFragSetup.class
```

## Shellcode (ARM32 Thumb-2)

```sh
NDK="$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
"$NDK/armv7a-linux-androideabi28-clang" \
    -nostdlib -static -Wl,--oformat=binary -Wl,-Ttext=0 \
    -o bin/df_shellcode.bin src/shellcode_v6.S
```

## Exploit (ARM32 static)

```sh
"$NDK/armv7a-linux-androideabi28-clang" -static -O2 -o bin/dirtyfrag_exploit src/dirtyfrag_exploit.c
```

## Splicehelper (ARM32 static)

```sh
"$NDK/armv7a-linux-androideabi28-clang" \
    -nostdlib -static -Os -Wl,-Ttext=0 \
    -o bin/splicehelper src/splicehelper.c
```

## Kernel module (ARM64)

Requires the kernel source tree in `$KDIR` with an `autoconf.h` that contains the fixed struct module layout: `CONFIG_DEBUG_INFO_BTF_MODULES=1` and `CONFIG_PAHOLE_VERSION=119`.

```sh
TC="$KERNEL_TC"
MDIR="$(pwd)/src"

PATH="$TC:$PATH" make -C "$KDIR" M="$MDIR" \
    CC="$TC/clang" LD="$TC/ld.lld" AR="$TC/llvm-ar" \
    NM="$TC/llvm-nm" OBJCOPY="$TC/llvm-objcopy" STRIP="$TC/llvm-strip" \
    LLVM=1 LLVM_IAS=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    KBUILD_EXTRA_SYMBOLS="$MDIR/Module.symvers.watch4" modules

"$TC/llvm-strip" --strip-unneeded src/dfroot_w4.ko
cp src/dfroot_w4.ko bin/
```

`Module.symvers.watch4` contains the symbol CRCs extracted from vmlinux. For a new firmware, extract them again.

## After a firmware change

1. Extract `boot.img` from the new package and the new `vmlinux` from the kernel
2. Check `CONFIG_*` in the new `/proc/config.gz` (struct module layout)
3. Extract the symbol CRCs from the new vmlinux into `Module.symvers.watch4`
4. Rebuild the KO against the new kernel tree
5. Patch boot.img with Magisk (`SKILL.md`, step 1; the ADB shell route needs no tap on the watch)
6. Run the chain with the new binaries

## adbkeeper APK

The adbkeeper APK does not depend on the firmware version. `adbkeeper/build.sh` builds it with the SDK from `ANDROID_SDK` (see Environment), which needs platform `android-36` and build-tools `36.0.0` in the same SDK. The script also needs a JDK (`javac`, `keytool`) and `zip`.

```sh
sh adbkeeper/build.sh
```

The output is `adbkeeper/build/gw4-adb-keeper.apk`. The script signs it with `adbkeeper/build/debug.keystore`, which it creates on the first run and then reuses. A keystore from another machine gives a different signature, and so does the key behind `apk/gw4-adb-keeper.apk`. `adb install -r` over an installed APK with another signature fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: uninstall the old version first. The uninstall also clears the `pm grant`, so repeat it after the install.
