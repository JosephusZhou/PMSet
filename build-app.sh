#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION=""
SIGN_IDENTITY="-"  # 默认 ad-hoc 签名
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "==> swift build (release)"
swift build -c release

echo "==> verifying Helper Info.plist embedded"
# 检查 Helper 二进制是否包含 __info_plist section（SMJobBless 必需）
if otool -s __TEXT __info_plist .build/release/PMSetHelper >/dev/null 2>&1; then
    echo "    OK: __info_plist section found"
else
    echo "    ERROR: Helper binary missing __info_plist section"
    echo "    Check Package.swift linkerSettings and Sources/PMSetHelper/Info.plist"
    exit 1
fi

echo "==> generating icon"
if [ ! -f "PMSet.icns" ]; then
    swift make-icon.swift
    rm -rf icon.iconset && mkdir -p icon.iconset
    sips -z 16 16 icon-1024.png --out icon.iconset/icon_16x16.png >/dev/null
    sips -z 32 32 icon-1024.png --out icon.iconset/icon_16x16@2x.png >/dev/null
    sips -z 32 32 icon-1024.png --out icon.iconset/icon_32x32.png >/dev/null
    sips -z 64 64 icon-1024.png --out icon.iconset/icon_32x32@2x.png >/dev/null
    sips -z 128 128 icon-1024.png --out icon.iconset/icon_128x128.png >/dev/null
    sips -z 256 256 icon-1024.png --out icon.iconset/icon_128x128@2x.png >/dev/null
    sips -z 256 256 icon-1024.png --out icon.iconset/icon_256x256.png >/dev/null
    sips -z 512 512 icon-1024.png --out icon.iconset/icon_256x256@2x.png >/dev/null
    sips -z 512 512 icon-1024.png --out icon.iconset/icon_512x512.png >/dev/null
    cp icon-1024.png icon.iconset/icon_512x512@2x.png
    iconutil -c icns icon.iconset -o PMSet.icns
    rm -rf icon.iconset icon-1024.png
fi

echo "==> assembling PMSet.app"
APP=PMSet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchServices"

# 主程序
cp .build/release/PMSet "$APP/Contents/MacOS/PMSet"

# 特权 Helper Tool
# SMJobBless 要求：
#   1. 必须放在 Contents/Library/LaunchServices/ 目录下
#   2. 文件名必须与 Helper 的 CFBundleIdentifier 完全一致
#   3. 二进制必须内置 Info.plist（__TEXT,__info_plist section）
cp .build/release/PMSetHelper "$APP/Contents/Library/LaunchServices/local.pmset.helper"

cp PMSet.icns "$APP/Contents/Resources/PMSet.icns"
cp Info.plist "$APP/Contents/Info.plist"

if [[ -n "$VERSION" ]]; then
    echo "==> setting version to $VERSION"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

echo "==> signing with identity: $SIGN_IDENTITY"
# 签名顺序：先签名内部的 Helper 二进制，再签名整个 App bundle。
# 注意：Helper 必须先签名，App 签名时会把 Helper 的签名纳入 seal。
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Library/LaunchServices/local.pmset.helper"
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "==> verifying code signature"
codesign --verify --deep --strict "$APP" && echo "    OK: signature valid"

echo "==> signature details"
codesign -dvv "$APP" 2>&1 | head -8 || true
echo "    ---"
codesign -dvv "$APP/Contents/Library/LaunchServices/local.pmset.helper" 2>&1 | head -8 || true

echo "==> done: $PWD/$APP"
