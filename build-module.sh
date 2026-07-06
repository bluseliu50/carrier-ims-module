#!/usr/bin/env bash
# build-module.sh — compile the applier to dex, then assemble the install zip.
#
# Prerequisites: JDK 21+ and Android SDK with build-tools (d8) and platform 36.
# Run from the repo root.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(grep -m1 '^version=' module.prop | cut -d= -f2 | tr -d ' \r')"
OUT="../carrier-ims-${VERSION}.zip"

# ---- Locate Android SDK ----
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
PLATFORM_JAR="$ANDROID_HOME/platforms/android-36/android.jar"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_HOME"/build-tools/*/ 2>/dev/null | tail -1)
D8="${BUILD_TOOLS_DIR}d8"

if [ ! -f "$PLATFORM_JAR" ]; then
    echo "!! android.jar not found at $PLATFORM_JAR"
    echo "   Set ANDROID_HOME to your SDK root (needs platforms;android-36)."
    exit 1
fi
if [ ! -f "$D8" ]; then
    echo "!! d8 not found in $ANDROID_HOME/build-tools/"
    exit 1
fi

echo ">> Compiling Applier.java…"
rm -rf build
mkdir -p build/classes
javac --release 11 -cp "$PLATFORM_JAR" -d build/classes applier/src/Applier.java

echo ">> Compiling to dex…"
mkdir -p system/bin
"$D8" --min-api 33 --output system/bin build/classes/Applier.class
echo "   -> system/bin/Applier.dex"

echo ">> Packing module zip → $OUT"
rm -f "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/system/bin" "$STAGE/bin" "$STAGE/webroot"
cp -f module.prop customize.sh service.sh uninstall.sh update.json "$STAGE"/
cp -f bin/*.sh "$STAGE/bin/"
cp -f webroot/index.html webroot/app.js webroot/style.css "$STAGE/webroot/"
cp -f system/bin/Applier.dex "$STAGE/system/bin/"

(cd "$STAGE" && zip -qr "$OLDPWD/$OUT" .)

echo "✓ Built $OUT"
echo "  Contents:"
unzip -l "$OUT"
