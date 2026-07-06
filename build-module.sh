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

# Stage only the runtime files into a temp dir so the install zip carries no
# build-time-only content (gradle, privapp source, README, AGENTS.md, etc.).
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/system/priv-app/CarrierImsApplier" \
         "$STAGE/system/etc/permissions" \
         "$STAGE/bin" \
         "$STAGE/webroot"
cp -f module.prop customize.sh service.sh uninstall.sh update.json "$STAGE"/
cp -f bin/*.sh "$STAGE/bin/"
cp -f webroot/index.html webroot/app.js webroot/style.css "$STAGE/webroot/"
cp -f system/etc/permissions/privapp-permissions-carrier_ims.xml "$STAGE/system/etc/permissions/"
cp -f system/priv-app/CarrierImsApplier/CarrierImsApplier.apk "$STAGE/system/priv-app/CarrierImsApplier/"

(cd "$STAGE" && zip -qr "$OLDPWD/$OUT" .)

echo "✓ Built $OUT"
echo "  Contents:"
unzip -l "$OUT"
