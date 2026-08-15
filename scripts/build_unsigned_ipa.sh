#!/usr/bin/env bash

set -euo pipefail

APP_SCHEME="Zhihu15"
APP_NAME="Zhihu15"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
PAYLOAD_DIR="$BUILD_DIR/Payload"
VERSION="${1:-1.0.0}"
OUT_IPA="zhihu15-${VERSION}.ipa"

mkdir -p "$BUILD_DIR"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Run this script on macOS with Xcode installed." >&2
  exit 1
fi
if [[ "${REGENERATE_XCODE_PROJECT:-0}" == "1" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "REGENERATE_XCODE_PROJECT=1 requires xcodegen. Install it with: brew install xcodegen" >&2
    exit 1
  fi
  echo "[1/4] xcodegen generate"
  xcodegen generate
else
  echo "[1/4] use committed Xcode project"
fi

SDK_ARGUMENT="${IOS_SDK:-iphoneos}"
SDK_VERSION="$(xcrun --sdk "$SDK_ARGUMENT" --show-sdk-version 2>/dev/null || true)"
if [[ "${REQUIRE_IOS15_SDK:-0}" == "1" && ! "$SDK_VERSION" =~ ^15\. ]]; then
  echo "iOS 15 SDK is required, but selected SDK is $SDK_VERSION." >&2
  echo "Select an Xcode installation that contains iPhoneOS 15.x.sdk via DEVELOPER_DIR." >&2
  exit 1
fi
echo "Using SDK: $SDK_ARGUMENT ($SDK_VERSION)"

echo "[2/4] xcodebuild archive"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -sdk "$SDK_ARGUMENT" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION=1 \
  INFOPLIST_KEY_CFBundleShortVersionString="$VERSION" \
  archive

echo "[3/4] copy app into Payload"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archived app not found at: $APP_PATH" >&2
  exit 1
fi
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

echo "[4/4] package unsigned IPA"
(
  cd "$BUILD_DIR"
  rm -f "$OUT_IPA"
  ditto -c -k --sequesterRsrc --keepParent Payload "$OUT_IPA"
)
rm -rf "$PAYLOAD_DIR"

echo "Generated: $BUILD_DIR/$OUT_IPA"
