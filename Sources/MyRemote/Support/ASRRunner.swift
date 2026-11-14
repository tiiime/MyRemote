import Foundation

/// 命令行语音测试：`MyRemote --asr <wav 路径>`。
/// 用本地模型转写一段 WAV，便于验证模型与推理链路是否正常。
enum ASRRunner {

    static func run(wavPath: String) -> Bool {
        let directory = ConfigStore.modelDirectory
        let modelPath = directory.appendingPathComponent("model.int8.onnx").path
        let tokensPath = directory.appendingPathComponent("tokens.txt").path

        guard FileManager.default.fileExists(atPath: modelPath) else {
            print("找不到模型：\(modelPath)")
            return false
        }
        guard FileManager.default.fileExists(atPath: tokensPath) else {
            print("找不到 tokens：\(tokensPath)")
            return false
        }
        guard let wave = WavReader.read(path: wavPath) else {
            print("无法读取 WAV：\(wavPath)")
            return false
        }

        var samples = wave.samples
        let sampleRate = wave.sampleRate
        if sampleRate != 16000 {
            samples = resample(samples, from: sampleRate, to: 16000)
        }

        let engine = SenseVoiceEngine()
        do {
            try engine.load(modelPath: modelPath, tokensPath: tokensPath, language: "auto", useItn: true)
            let transcript = try engine.transcribe(samples: samples)
            print("语言: \(transcript.language)  情感: \(transcript.emotion)  耗时: \(String(format: "%.2f", transcript.duration))s")
            print(transcript.text)
            return !transcript.text.isEmpty
        } catch {
            print("识别失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 线性重采样（仅用于调试输入，不是产品路径）。
    private static func resample(_ input: [Float], from sourceRate: Int, to targetRate: Int) -> [Float] {
        guard sourceRate != targetRate, !input.isEmpty else { return input }
        let ratio = Double(sourceRate) / Double(targetRate)
        let outputCount = Int(Double(input.count) / ratio)
        var output = [Float](repeating: 0, count: outputCount)
        for index in 0..<outputCount {
            let position = Double(index) * ratio
            let lower = Int(position)
            let upper = min(lower + 1, input.count - 1)
            let fraction = Float(position - Double(lower))
            output[index] = input[lower] * (1 - fraction) + input[upper] * fraction
        }
        return output
    }
}
