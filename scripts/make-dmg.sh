#!/bin/zsh
# 打包 DMG：dist/MyRemote-<version>.dmg
set -e
cd "$(dirname "$0")/.."

./scripts/package.sh >/dev/null

VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info-app.plist)"
DMG="dist/MyRemote-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "MyRemote" -srcfolder "dist/MyRemote.app" -ov -format UDZO "$DMG" >/dev/null
echo "==> 已生成：$DMG"
