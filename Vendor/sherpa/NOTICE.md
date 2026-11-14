# sherpa-onnx runtime

`lib/libsherpa-onnx-c-api.dylib` 与 `lib/libonnxruntime.dylib` 来自
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)（Apache License 2.0），
由 `scripts/fetch-sherpa.sh` 从 npm 包 `sherpa-onnx-darwin-arm64` 提取。

SenseVoice 模型来自 [FunAudioLLM/SenseVoice](https://github.com/FunAudioLLM/SenseVoice)，
通过 HuggingFace 仓库 `csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`
在运行时下载，不随本仓库分发。
