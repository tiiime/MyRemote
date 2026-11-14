#!/bin/zsh
# 构建 MyRemote。
#   ./scripts/build.sh             release 构建
#   ./scripts/build.sh --debug     debug 构建
set -e
cd "$(dirname "$0")/.."

CONFIG=release
if [[ "$1" == "--debug" ]]; then CONFIG=debug; fi

LIB_DIR="Vendor/sherpa/lib"
if [[ ! -f "$LIB_DIR/libsherpa-onnx-c-api.dylib" || ! -f "$LIB_DIR/libonnxruntime.dylib" ]]; then
  echo "==> Vendor/sherpa 缺少 dylib，尝试从 PyPI 提取"
  ./scripts/fetch-sherpa.sh
fi

# 把 SwiftPM / clang 的缓存都收进工程目录，避免写 ~/Library 与 /var/folders
# （受限环境或只读 HOME 下也能构建）。
export TMPDIR="$PWD/.cache/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/swiftmodule"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" .cache/swiftpm

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --disable-sandbox --cache-path "$PWD/.cache/swiftpm"

BIN_DIR=".build/$CONFIG"
# rpath 是 @executable_path，把 dylib 放到二进制旁边，开发时直接可跑。
cp -f "$LIB_DIR"/*.dylib "$BIN_DIR"/

# 本地化资源跟着二进制走：直接跑 .build/$CONFIG/MyRemote 时也能按语言切换。
for lproj in Resources/*.lproj; do
  [[ -d "$lproj" ]] || continue
  rm -rf "$BIN_DIR/$(basename "$lproj")"
  cp -R "$lproj" "$BIN_DIR/"
done

echo "==> 构建完成：$BIN_DIR/MyRemote"
echo "    自检: $BIN_DIR/MyRemote --self-test"
