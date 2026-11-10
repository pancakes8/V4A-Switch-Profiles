#!/usr/bin/env bash
# Baut aus module/ und der fertigen APK das flashbare Magisk-Modul (dist/*.zip).
# Aufruf: bash pack-module.sh [pfad/zur/V4ASwitch.apk]
set -euo pipefail
cd "$(dirname "$0")"

APK="${1:-build/V4ASwitch.apk}"
[ -f "$APK" ] || { echo "APK nicht gefunden: $APK"; exit 1; }

VER=$(sed -n 's/^version=//p' module/module.prop | head -n 1)
OUT="dist/V4A-Profile-Switch-$VER.zip"

rm -rf dist
mkdir -p dist/stage/system/app/V4ASwitch
cp -r module/. dist/stage/
cp "$APK" dist/stage/system/app/V4ASwitch/V4ASwitch.apk
(cd dist/stage && zip -q -r -9 "../$(basename "$OUT")" .)
rm -rf dist/stage
echo "Modul: $OUT"
