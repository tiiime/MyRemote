#!/bin/zsh
# 获取 sherpa-onnx 的 macOS 动态库到 Vendor/sherpa/lib。
#
# 优先从 npm 包 sherpa-onnx-darwin-arm64 下载（体积小、速度快），
# 失败时回退到 PyPI 的 sherpa-onnx-core wheel。
# sherpa-onnx 是 Apache-2.0，版权归 k2-fsa 所有。
set -e
cd "$(dirname "$0")/.."

VERSION="${SHERPA_VERSION:-2.0.1}"
mkdir -p Vendor/sherpa/lib
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

download_npm() {
  local url
  url="$(curl -s -m 20 "https://registry.npmjs.org/sherpa-onnx-darwin-arm64" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['versions']['$VERSION']['dist']['tarball'])")" || return 1
  [[ -n "$url" ]] || return 1
  echo "==> 下载 $url"
  curl -sL -m 300 -o "$TMP/sherpa.tgz" "$url" || return 1
  tar -xzf "$TMP/sherpa.tgz" -C "$TMP" || return 1
  cp "$TMP"/package/*.dylib Vendor/sherpa/lib/
}

download_pypi() {
  echo "==> 回退到 PyPI sherpa-onnx-core"
  pip3 download "sherpa-onnx-core==$VERSION" \
    --only-binary=:all: --platform macosx_11_0_arm64 --python-version 3.12 --no-deps \
    -d "$TMP" >/dev/null || return 1
  local whl
  whl="$(ls "$TMP"/sherpa_onnx_core-*.whl | head -1)"
  unzip -q -o "$whl" -d "$TMP/x" || return 1
  find "$TMP/x" -name "*.dylib" -exec cp {} Vendor/sherpa/lib/ \;
}

if ! download_npm; then
  download_pypi
fi

if [[ ! -f Vendor/sherpa/lib/libsherpa-onnx-c-api.dylib || ! -f Vendor/sherpa/lib/libonnxruntime.dylib ]]; then
  echo "提取失败：未找到 dylib"
  exit 1
fi

echo "==> 已就绪"
ls -la Vendor/sherpa/lib
