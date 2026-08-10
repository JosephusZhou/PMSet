#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "==> swift build (release)"
swift build -c release

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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PMSet "$APP/Contents/MacOS/PMSet"
cp PMSet.icns "$APP/Contents/Resources/PMSet.icns"
cp Info.plist "$APP/Contents/Info.plist"

if [[ -n "$VERSION" ]]; then
    echo "==> setting version to $VERSION"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

echo "==> ad-hoc signing"
codesign --force --sign - "$APP"

echo "==> done: $PWD/$APP"
