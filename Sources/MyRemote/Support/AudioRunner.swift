import Foundation

/// 调试：`MyRemote --test-blackhole` 把一段 440Hz 测试音写进 BlackHole，
/// 便于用录音软件确认虚拟声卡链路是否打通。
enum AudioRunner {

    static func testBlackHole(deviceName: String = "BlackHole 2ch",
                              seconds: Double = 1.5) -> Bool {
        print("BlackHole 驱动安装：\(AudioDevices.blackHoleInstalled ? "是" : "否")")
        print("BlackHole 设备在线：\(AudioDevices.findOutputDevice(namePrefix: deviceName) != nil ? "是" : "否")")

        let bridge = BlackHoleBridge(deviceNamePrefix: deviceName)
        guard bridge.isDeviceAvailable else {
            print("找不到输出设备 \(deviceName)，请先安装 BlackHole 2ch")
            return false
        }

        bridge.streamStarted(sampleRate: 16000)
        Thread.sleep(forTimeInterval: 0.4)
        guard bridge.isRunningNow else {
            print("音频引擎启动失败（检查 BlackHole 是否被占用或采样率异常）")
            return false
        }

        let total = Int(16000 * seconds)
        var chunk: [Int16] = []
        chunk.reserveCapacity(1600)
        for i in 0..<total {
            let t = Double(i) / 16000
            let fade = min(1.0, min(t / 0.05, (seconds - t) / 0.05))
            let value = sin(2 * Double.pi * 440 * t) * 12_000 * fade
            chunk.append(Int16(value))
            if chunk.count == 1600 {
                bridge.write(chunk)
                chunk.removeAll(keepingCapacity: true)
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        if !chunk.isEmpty { bridge.write(chunk) }

        Thread.sleep(forTimeInterval: 0.6)
        bridge.streamStopped()
        Thread.sleep(forTimeInterval: 0.6)
        print("已向 \(deviceName) 输出 \(seconds)s / 440Hz 测试音")
        return true
    }
}
