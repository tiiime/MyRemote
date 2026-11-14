# scripts

- `build.sh`：release / debug 构建（缓存收在工程内）。
- `package.sh`：构建并打包 `dist/MyRemote.app`。默认 ad-hoc 签名；
  设置 `MYREMOTE_SIGN_IDENTITY` 可使用固定签名身份（推荐本地开发）。
- `fetch-sherpa.sh`：从 PyPI 提取 sherpa-onnx 运行时 dylib。
- `make-dmg.sh`：生成 DMG。
