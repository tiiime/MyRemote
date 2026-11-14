import Foundation
import CSherpa

/// SenseVoiceSmall 本地离线识别（sherpa-onnx C API）。
///
/// 模型：sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17（int8，约 230MB）
/// 输入：16kHz 单声道 float32；输出：UTF-8 文本（含语言/情感标签）。
final class SenseVoiceEngine {

    private var recognizer: OpaquePointer?
    private let queue = DispatchQueue(label: "com.myremote.asr")
    private(set) var modelPath = ""
    private(set) var tokensPath = ""
    private(set) var language = "auto"
    private(set) var useItn = true

    var isReady: Bool { queue.sync { recognizer != nil } }

    /// 加载（或热切换）识别器。重复调用会销毁旧实例。
    func load(modelPath: String, tokensPath: String, language: String = "auto", useItn: Bool = true) throws {
        try queue.sync {
            if let old = recognizer {
                SherpaOnnxDestroyOfflineRecognizer(old)
                recognizer = nil
            }
            let engine = Self.makeRecognizer(modelPath: modelPath, tokensPath: tokensPath,
                                             language: language, useItn: useItn)
            guard let engine else {
                throw NSError(domain: "SenseVoice", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "识别器创建失败（模型或 tokens 无效）"])
            }
            recognizer = engine
            self.modelPath = modelPath
            self.tokensPath = tokensPath
            self.language = language
            self.useItn = useItn
        }
    }

    func unload() {
        queue.sync {
            if let old = recognizer {
                SherpaOnnxDestroyOfflineRecognizer(old)
                recognizer = nil
            }
        }
    }

    struct Transcript {
        var text: String
        var language: String
        var emotion: String
        var event: String
        var duration: TimeInterval
    }

    /// 同步识别整段音频（已在后台队列调用）。
    func transcribe(samples: [Float], sampleRate: Int = 16000) throws -> Transcript {
        try queue.sync {
            guard let recognizer else {
                throw NSError(domain: "SenseVoice", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "模型未加载"])
            }
            guard !samples.isEmpty else {
                throw NSError(domain: "SenseVoice", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "空音频"])
            }
            let start = Date()
            guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
                throw NSError(domain: "SenseVoice", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "无法创建识别流"])
            }
            SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), samples, Int32(samples.count))
            SherpaOnnxDecodeOfflineStream(recognizer, stream)

            var transcript = Transcript(text: "", language: "", emotion: "", event: "", duration: 0)
            if let result = SherpaOnnxGetOfflineStreamResult(stream) {
                let pointer = result.pointee
                if let text = pointer.text {
                    transcript.text = String(cString: text)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let lang = pointer.lang { transcript.language = Self.stripTags(String(cString: lang)) }
                if let emotion = pointer.emotion { transcript.emotion = Self.stripTags(String(cString: emotion)) }
                if let event = pointer.event { transcript.event = Self.stripTags(String(cString: event)) }
                SherpaOnnxDestroyOfflineRecognizerResult(result)
            }
            SherpaOnnxDestroyOfflineStream(stream)
            transcript.duration = Date().timeIntervalSince(start)
            return transcript
        }
    }

    /// 去掉 `<|zh|>` 一类控制标签。
    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 构造

    private static func makeRecognizer(modelPath: String, tokensPath: String,
                                       language: String, useItn: Bool) -> OpaquePointer? {
        var config = SherpaOnnxOfflineRecognizerConfig()
        withUnsafeMutableBytes(of: &config) { $0.initializeMemory(as: UInt8.self, repeating: 0) }

        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80
        config.model_config.num_threads = 2
        config.model_config.debug = 0
        config.model_config.provider = Self.cString("cpu")
        config.model_config.sense_voice.model = Self.cString(modelPath)
        config.model_config.sense_voice.language = Self.cString(language)
        config.model_config.sense_voice.use_itn = useItn ? 1 : 0
        config.model_config.tokens = Self.cString(tokensPath)
        config.decoding_method = Self.cString("greedy_search")

        let engine = SherpaOnnxCreateOfflineRecognizer(&config)

        // 配置里的字符串已经被识别器拷贝，释放临时 C 字符串。
        for pointer in [config.model_config.provider,
                        config.model_config.sense_voice.model,
                        config.model_config.sense_voice.language,
                        config.model_config.tokens,
                        config.decoding_method] {
            free(UnsafeMutablePointer(mutating: pointer))
        }
        return engine
    }

    private static func cString(_ value: String) -> UnsafePointer<CChar>? {
        guard let pointer = strdup(value) else { return nil }
        return UnsafePointer(pointer)
    }
}
