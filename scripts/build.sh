#!/usr/bin/env bash
# Build Cyanide for iphoneos and package the resulting .app into a versioned IPA
# under build/, e.g. build/Cyanide-1.0.14.ipa, with a build/Cyanide.ipa
# symlink pointing at the latest build. With SDK=iphonesimulator, build the
# simulator .app and skip IPA packaging.
#
# Run as: ./scripts/build.sh
# Override defaults with env vars:
#   SCHEME, CONFIG (Debug|Release), SDK (iphoneos|iphonesimulator)
#
# The version comes from CFBundleShortVersionString in the built Info.plist
# (= the MARKETING_VERSION build setting in the xcodeproj). Bump
# MARKETING_VERSION to ship a new version.
#
# Code signing is disabled — the IPA ships unsigned for sideload via
# AltStore / TrollStore / Sideloadly, which do their own signing.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="${SCHEME:-Cyanide}"
CONFIG="${CONFIG:-Debug}"
SDK="${SDK:-iphoneos}"
PROJECT="Cyanide.xcodeproj"
DERIVED="$PWD/build/DerivedData"
PRODUCT_DIR="$DERIVED/Build/Products/${CONFIG}-${SDK}"
APP_NAME="Cyanide.app"
IPA_LATEST="$PWD/build/Cyanide.ipa"
XCODEBUILD_EXTRA=()

if [ "$SDK" = "iphonesimulator" ]; then
    XCODEBUILD_EXTRA=(ARCHS=arm64 ONLY_ACTIVE_ARCH=YES)
fi

mkdir -p build

echo "==> xcodebuild ($SCHEME / $CONFIG / $SDK)"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -sdk "$SDK" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    ${XCODEBUILD_EXTRA[@]+"${XCODEBUILD_EXTRA[@]}"} \
    build \
    | xcbeautify --quiet 2>/dev/null \
    || xcodebuild \
         -project "$PROJECT" \
         -scheme "$SCHEME" \
         -sdk "$SDK" \
         -configuration "$CONFIG" \
         -derivedDataPath "$DERIVED" \
         CODE_SIGNING_ALLOWED=NO \
         ${XCODEBUILD_EXTRA[@]+"${XCODEBUILD_EXTRA[@]}"} \
         build

APP_PATH="$PRODUCT_DIR/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo "error: $APP_PATH not found after build" >&2
    exit 1
fi

if [ "$SDK" = "iphonesimulator" ]; then
    echo "==> simulator app $APP_PATH"
    exit 0
fi

HELPER_SRC="$PWD/scripts/vphone_krw_helper.c"
HELPER_ENT="$PWD/scripts/vphone_krw_helper.entitlements"
HELPER_OUT="$APP_PATH/vphone_krw_helper"
if [ -f "$HELPER_SRC" ]; then
    echo "==> building vphone KRW helper"
    xcrun -sdk iphoneos clang \
        -arch arm64 \
        -miphoneos-version-min=15.0 \
        "$HELPER_SRC" \
        -o "$HELPER_OUT"
    chmod 755 "$HELPER_OUT"
    if command -v ldid >/dev/null 2>&1 && [ -f "$HELPER_ENT" ]; then
        ldid -S"$HELPER_ENT" "$HELPER_OUT"
    fi
fi

BRIDGE_SRC="$PWD/scripts/vphone_springboard_bridge.m"
BRIDGE_OUT="$APP_PATH/vphone_springboard_bridge.dylib"
if [ -f "$BRIDGE_SRC" ]; then
    echo "==> building vphone SpringBoard bridge"
    xcrun -sdk iphoneos clang \
        -dynamiclib \
        -arch arm64 \
        -arch arm64e \
        -miphoneos-version-min=15.0 \
        "$BRIDGE_SRC" \
        -framework CoreFoundation \
        -framework Foundation \
        -o "$BRIDGE_OUT"
    chmod 755 "$BRIDGE_OUT"
    if command -v ldid >/dev/null 2>&1; then
        # This dylib is injected into SpringBoard by TweakLoader/Substrate.
        # Do not reuse the privileged helper entitlements here: SpringBoard's
        # AMFI constraint checks reject third-party tweak dylibs that carry
        # app/helper entitlements before the constructor can start the bridge.
        ldid -S "$BRIDGE_OUT"
    fi
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Info.plist" 2>/dev/null || true)
if [ -z "$VERSION" ]; then
    echo "error: could not read CFBundleShortVersionString from $APP_PATH/Info.plist" >&2
    exit 1
fi

IPA_OUT="$PWD/build/Cyanide-${VERSION}.ipa"
IPA_BASENAME="$(basename "$IPA_OUT")"
LATEST_BASENAME="$(basename "$IPA_LATEST")"

echo "==> packaging $IPA_OUT (version $VERSION)"
STAGE="$(mktemp -d -t cyanide-ipa)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/"
rm -f "$IPA_OUT"
( cd "$STAGE" && zip -qry "$IPA_OUT" Payload )

# Keep an unversioned symlink so tooling / README references that expect the
# legacy path still resolve to the latest build.
rm -f "$IPA_LATEST"
( cd "$PWD/build" && ln -s "$IPA_BASENAME" "$LATEST_BASENAME" )

SIZE=$(du -h "$IPA_OUT" | cut -f1)
echo "==> wrote $IPA_OUT ($SIZE)"
echo "==> symlink $IPA_LATEST -> $IPA_BASENAME"
