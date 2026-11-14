import Foundation
import AVFoundation

/// 模式切换音效：短促、舒适的三套提示音，运行时合成，不依赖音频素材。
///
/// - 默认（normal）：柔和的两音上行（C5→E5），舒缓；
/// - 命令（command）：三音快速上行（E5→A5→C6），活跃；
/// - 输入（input）：两声轻快的键盘点击。
final class ModeSounds {

    static let shared = ModeSounds()

    private var players: [VoiceMode: AVAudioPlayer] = [:]
    private let lock = NSLock()

    private init() {
        for mode in VoiceMode.allCases {
            guard let data = Self.wav(for: mode),
                  let player = try? AVAudioPlayer(data: data) else { continue }
            player.volume = Self.volume(for: mode)
            player.prepareToPlay()
            players[mode] = player
        }
    }

    func play(_ mode: VoiceMode) {
        lock.lock()
        let player = players[mode]
        lock.unlock()
        guard let player else { return }
        DispatchQueue.main.async {
            player.stop()
            player.currentTime = 0
            player.play()
        }
    }

    /// 调试/试听：导出三套音效为 WAV。
    @discardableResult
    static func export(to directory: String) -> Bool {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for mode in VoiceMode.allCases {
            guard let data = wav(for: mode) else { return false }
            do {
                try data.write(to: dir.appendingPathComponent("\(mode.rawValue).wav"))
            } catch {
                return false
            }
        }
        return true
    }

    // MARK: - 音量

    private static func volume(for mode: VoiceMode) -> Float {
        switch mode {
        case .forward: return 0.5
        case .command: return 0.42
        case .input: return 0.38
        }
    }

    // MARK: - 合成

    private static let sampleRate = 44100.0

    private static func wav(for mode: VoiceMode) -> Data? {
        let samples: [Float]
        switch mode {
        case .forward: samples = calm()
        case .command: samples = command()
        case .input: samples = keyboard()
        }
        return encodeWAV(samples)
    }

    /// 柔和的两音上行：C5 → E5。
    private static func calm() -> [Float] {
        var samples: [Float] = []
        samples += tone(523.25, duration: 0.13, amplitude: 0.20,
                        attack: 0.012, release: 0.06, harmonic: 0.10)
        samples += tone(659.25, duration: 0.22, amplitude: 0.18,
                        attack: 0.01, release: 0.12, harmonic: 0.12)
        return samples
    }

    /// 三音快速上行：E5 → A5 → C6。
    private static func command() -> [Float] {
        var samples: [Float] = []
        samples += tone(659.25, duration: 0.06, amplitude: 0.24,
                        attack: 0.004, release: 0.035, harmonic: 0.25)
        samples += tone(880.00, duration: 0.06, amplitude: 0.24,
                        attack: 0.004, release: 0.035, harmonic: 0.25)
        samples += tone(1046.50, duration: 0.09, amplitude: 0.22,
                        attack: 0.004, release: 0.06, harmonic: 0.20)
        return samples
    }

    /// 两声轻快键盘点击。
    private static func keyboard() -> [Float] {
        let total = Int(sampleRate * 0.16)
        var samples = [Float](repeating: 0, count: total)
        for click in 0..<2 {
            let start = Int(sampleRate * (0.0 + Double(click) * 0.075))
            let length = Int(sampleRate * 0.014)
            for i in 0..<length {
                let index = start + i
                guard index < total else { break }
                let t = Double(i) / sampleRate
                let env = exp(-Double(i) / (sampleRate * 0.0026))
                let noise = Double.random(in: -1...1)
                let value = noise * 0.30 * env
                    + sin(2 * Double.pi * 1900 * t) * 0.16 * env
                    + sin(2 * Double.pi * 180 * t) * 0.08 * env
                samples[index] += Float(value)
            }
        }
        return samples
    }

    private static func tone(_ frequency: Double, duration: Double,
                             amplitude: Double, attack: Double,
                             release: Double, harmonic: Double) -> [Float] {
        let count = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let progress = Double(i) / Double(max(1, count - 1))
            let attackGain = attack > 0 ? min(1.0, t / attack) : 1
            let releaseGain = release > 0 ? min(1.0, (duration - t) / release) : 1
            let envelope = max(0, min(attackGain, releaseGain))
            let wave = sin(2 * Double.pi * frequency * t)
                + harmonic * sin(2 * Double.pi * frequency * 2 * t)
            samples[i] = Float(wave * amplitude * envelope * (1 - 0.1 * progress))
        }
        return samples
    }

    // MARK: - WAV

    private static func encodeWAV(_ samples: [Float]) -> Data? {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(44100))
        append(UInt32(88200))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append(Int16(clamped * 32760))
        }
        return data
    }
}
