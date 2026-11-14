#!/bin/zsh
# 打包 MyRemote.app 到 dist/（ad-hoc 签名，首次运行需在系统设置里放行）。
set -e
cd "$(dirname "$0")/.."

./scripts/build.sh

APP="dist/MyRemote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/MyRemote" "$APP/Contents/MacOS/"
cp Vendor/sherpa/lib/*.dylib "$APP/Contents/MacOS/"
cp Resources/Info-app.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
# 本地化资源（zh 为基准文案，en 是翻译表）。
for lproj in Resources/*.lproj; do
  [[ -d "$lproj" ]] || continue
  rm -rf "$APP/Contents/Resources/$(basename "$lproj")"
  cp -R "$lproj" "$APP/Contents/Resources/"
done

mkdir -p "$APP/Contents/Resources/sherpa"
cp Vendor/sherpa/NOTICE.md "$APP/Contents/Resources/sherpa/NOTICE.md"

# 默认 ad-hoc 签名；设置 MYREMOTE_SIGN_IDENTITY 可换成固定的自签名/Developer ID，
# 这样 TCC（辅助功能、输入监控）在更新后仍认同一个 App。
SIGN_IDENTITY="${MYREMOTE_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep -s - "$APP" 2>/dev/null || true
  echo "==> 签名：ad-hoc（每次更新需要重新授权）"
else
  codesign --force --deep -s "$SIGN_IDENTITY" "$APP"
  echo "==> 签名：$SIGN_IDENTITY"
fi

echo "==> 已打包：$APP"
echo "    首次运行：右键 → 打开，或系统设置 → 隐私与安全性 → 仍要打开"
