import Foundation

/// 最小 WAV 读取器（PCM 16-bit，单/双声道；用于 --asr 调试与自测）。
enum WavReader {

    struct Wave {
        var samples: [Float]
        var sampleRate: Int
    }

    static func read(path: String) -> Wave? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return parse(data: data)
    }

    static func parse(data: Data) -> Wave? {
        guard data.count > 44,
              String(data: data.prefix(4), encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else { return nil }

        var offset = 12
        var sampleRate = 16000
        var channels = 1
        var bits = 16
        var pcmData: Data?

        while offset + 8 <= data.count {
            let id = String(data: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = Int(readUInt32(data, offset + 4))
            let bodyStart = offset + 8
            guard bodyStart + size <= data.count else { break }

            if id == "fmt " {
                let format = readUInt16(data, bodyStart)
                channels = Int(readUInt16(data, bodyStart + 2))
                sampleRate = Int(readUInt32(data, bodyStart + 4))
                bits = Int(readUInt16(data, bodyStart + 14))
                guard format == 1, bits == 16 else { return nil }
            } else if id == "data" {
                pcmData = data.subdata(in: bodyStart..<(bodyStart + size))
            }
            offset = bodyStart + size + (size % 2)
        }

        guard let pcm = pcmData, channels > 0 else { return nil }
        let frameCount = pcm.count / (2 * channels)
        var samples = [Float](repeating: 0, count: frameCount)
        pcm.withUnsafeBytes { raw in
            let ints = raw.bindMemory(to: Int16.self)
            for frame in 0..<frameCount {
                var sum: Int32 = 0
                for channel in 0..<channels {
                    sum += Int32(ints[frame * channels + channel])
                }
                samples[frame] = Float(sum) / Float(channels) / 32768.0
            }
        }
        return Wave(samples: samples, sampleRate: sampleRate)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data[offset..<offset + 4].enumerated().reduce(0) { value, pair in
            value | (UInt32(pair.element) << (8 * UInt32(pair.offset)))
        }
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
}
