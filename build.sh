#!/usr/bin/env bash
# Baut die App (nur Android-SDK-Werkzeuge, kein Gradle) und das flashbare Magisk-Modul.
# Voraussetzung: ANDROID_HOME zeigt auf ein Android SDK (build-tools + platforms >= 33), JDK 17+.
set -euo pipefail
cd "$(dirname "$0")"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -d "$SDK" ] || { echo "ANDROID_HOME ist nicht gesetzt oder existiert nicht."; exit 1; }

BT=$(ls -1 "$SDK/build-tools" | sort -V | tail -n 1)
PL=$(ls -1 "$SDK/platforms" | sed -n 's/^android-\([0-9][0-9]*\)$/\1/p' | sort -n | tail -n 1)
B="$SDK/build-tools/$BT"
AJ="$SDK/platforms/android-$PL/android.jar"
echo "build-tools $BT, platform android-$PL"

rm -rf build
mkdir -p build/gen build/classes build/dex

"$B/aapt2" compile --dir app/res -o build/res.zip
"$B/aapt2" link -o build/base.apk -I "$AJ" \
  --manifest app/AndroidManifest.xml -R build/res.zip --java build/gen \
  --min-sdk-version 24 --target-sdk-version 33 \
  --version-code 3 --version-name 1.2.0 --auto-add-overlay

javac -source 8 -target 8 -Xlint:-options -classpath "$AJ" -d build/classes \
  $(find app/src build/gen -name '*.java')

"$B/d8" --release --min-api 24 --lib "$AJ" --output build/dex \
  $(find build/classes -name '*.class')

cp build/base.apk build/unaligned.apk
(cd build/dex && zip -q ../unaligned.apk classes.dex)
"$B/zipalign" -f -p 4 build/unaligned.apk build/aligned.apk

KS=build/debug.keystore
keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
  -alias v4a -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=V4A Switch" >/dev/null 2>&1
"$B/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out build/V4ASwitch.apk build/aligned.apk

bash pack-module.sh build/V4ASwitch.apk
