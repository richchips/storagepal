#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DIST_DIR="$PROJECT_DIR/dist"
BUILD_DIR="$PROJECT_DIR/.build_release"
APP_DIR="$BUILD_DIR/StoragePal.app"
ZIP_PATH="$DIST_DIR/Storage Pal.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$BUILD_DIR/ModuleCache"

mkdir -p "$MODULE_CACHE" "$MACOS_DIR" "$RESOURCES_DIR" "$DIST_DIR"

BUILD_ARGS=(--package-path "$PROJECT_DIR" -c release --scratch-path "$BUILD_DIR" --disable-sandbox)
if [[ -n "${SDKROOT_OVERRIDE:-}" ]]; then
  env \
    SDKROOT="$SDKROOT_OVERRIDE" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build "${BUILD_ARGS[@]}"
else
  env \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build "${BUILD_ARGS[@]}"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp -X "$BUILD_DIR/release/StoragePal" "$MACOS_DIR/StoragePal"
cp -X "$PROJECT_DIR/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/StoragePal"

find "$APP_DIR" -type f -name "._*" -delete 2>/dev/null || true
find "$APP_DIR" -exec xattr -c {} + 2>/dev/null || true
xattr -c "$APP_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
codesign --force --sign - "$APP_DIR"
codesign -v "$APP_DIR"

rm -f "$ZIP_PATH"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "Packaged: $ZIP_PATH"
