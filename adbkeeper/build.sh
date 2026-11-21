#!/bin/sh
# Builds GW4 ADB Keeper into build/gw4-adb-keeper.apk.
# Needs ANDROID_SDK pointing at an SDK with platform android-36 and build-tools 36.0.0.
# build/debug.keystore survives the cleanup below: a new key per build makes
# `adb install -r` fail with INSTALL_FAILED_UPDATE_INCOMPATIBLE.
set -eu

: "${ANDROID_SDK:?set ANDROID_SDK to the Android SDK root}"
BT="$ANDROID_SDK/build-tools/36.0.0"
PLATFORM="$ANDROID_SDK/platforms/android-36/android.jar"
APP="$(cd "$(dirname "$0")" && pwd)"
OUT="$APP/build"
KEYSTORE="$OUT/debug.keystore"

rm -rf "$OUT/obj" "$OUT/bin" "$OUT/gw4-adb-keeper.apk"
mkdir -p "$OUT/obj" "$OUT/bin"

if [ ! -f "$KEYSTORE" ]; then
    keytool -genkeypair -keystore "$KEYSTORE" -alias androiddebugkey \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass android -keypass android \
        -dname "CN=Android Debug,O=Android,C=US"
fi

javac -source 11 -target 11 -cp "$PLATFORM" -d "$OUT/obj" "$APP/src/com/gw4root/adbkeeper/"*.java

"$BT/d8" "$OUT/obj/com/gw4root/adbkeeper/"*.class --output "$OUT/bin/" --lib "$PLATFORM"

"$BT/aapt2" compile -o "$OUT/bin/res.zip" --dir "$APP/res"

"$BT/aapt2" link -o "$OUT/bin/unsigned.apk" \
    --manifest "$APP/AndroidManifest.xml" \
    -I "$PLATFORM" --min-sdk-version 30 --target-sdk-version 36 \
    "$OUT/bin/res.zip"

cp "$OUT/bin/unsigned.apk" "$OUT/bin/tmp.apk"
zip -j "$OUT/bin/tmp.apk" "$OUT/bin/classes.dex" >/dev/null

"$BT/zipalign" -f 4 "$OUT/bin/tmp.apk" "$OUT/bin/aligned.apk"
"$BT/apksigner" sign \
    --ks "$KEYSTORE" --ks-pass pass:android \
    --key-pass pass:android --ks-key-alias androiddebugkey \
    --out "$OUT/gw4-adb-keeper.apk" "$OUT/bin/aligned.apk"

ls -la "$OUT/gw4-adb-keeper.apk"
