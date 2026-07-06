#!/usr/bin/env bash
# build-module.sh — assemble the installable KernelSU/Magisk/APatch zip.
#
# Prerequisites: JDK 17+ and Android SDK with platform 36 (compileSdk=36).
# Run from the repo root (carrier-ims-module/).
#
# Produces: ../carrier-ims-v<version>.zip  (version read from module.prop)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(grep -m1 '^version=' module.prop | cut -d= -f2 | tr -d ' \r')"
OUT="../carrier-ims-${VERSION}.zip"

echo ">> Building priv-app (CarrierImsApplier)…"
./gradlew :privapp:assembleRelease -q

APK_IN="privapp/build/outputs/apk/release/privapp-release.apk"
if [ ! -f "$APK_IN" ]; then
    # Some AGP versions name it *-unsigned.apk when not signed.
    APK_IN="privapp/build/outputs/apk/release/privapp-release-unsigned.apk"
fi
if [ ! -f "$APK_IN" ]; then
    echo "!! release apk not found"; exit 1
fi

echo ">> Placing APK + permissions into system/…"
mkdir -p system/priv-app/CarrierImsApplier
cp -f "$APK_IN" system/priv-app/CarrierImsApplier/CarrierImsApplier.apk

echo ">> Packing module zip → $OUT"
rm -f "$OUT"
# Exclude build artifacts, source-only dirs, and git; keep everything else.
zip -qr "$OUT" . \
    -x "privapp/build/*" "privapp/.gradle/*" ".gradle/*" \
       "webroot-src/*" "*.zip" ".git/*" "build-module.sh" "AGENTS.md"

echo "✓ Built $OUT"
echo "  Contents check:"
unzip -l "$OUT" | grep -E "CarrierImsApplier.apk|privapp-permissions|module.prop|webroot/index.html" || true
