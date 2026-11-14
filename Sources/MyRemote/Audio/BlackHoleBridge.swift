import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

// 把遥控器解码后的 16kHz PCM 实时写到指定输出设备（默认 "BlackHole 2ch"），
// 其他 App 把这个虚拟设备选作麦克风即可收到同一路语音。
// 体量/逻辑参考 MiRemote 的 AudioBridge（MIT）。

// MARK: - CoreAudio 设备工具

enum AudioDevices {

    static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        )
        guard status == noErr else { return [] }
        return ids
    }

    static func hasOutputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return false }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(
            capacity: Int(dataSize) / MemoryLayout<AudioBufferList>.stride + 1
        )
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList) == noErr
        else { return false }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        var channels: UInt32 = 0
        for buffer in buffers { channels += buffer.mNumberChannels }
        return channels > 0
    }

    static func name(of deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString? = nil
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr, let cf = name else { return nil }
        return cf as String
    }

    static func outputDeviceNames() -> [String] {
        allDeviceIDs()
            .filter { hasOutputStreams($0) }
            .compactMap { name(of: $0) }
    }

    static func findOutputDevice(namePrefix: String) -> AudioObjectID? {
        for id in allDeviceIDs() where hasOutputStreams(id) {
            if let n = name(of: id), n.hasPrefix(namePrefix) {
                return id
            }
        }
        return nil
    }

    /// BlackHole 驱动是否安装（不要求当前在线）。
    static var blackHoleInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver")
    }
}

// MARK: - 线程安全环形缓冲

private final class RingBuffer: @unchecked Sendable {
    private var storage: [Float]
    private let capacity: Int
    private var readIndex = 0
    private var writeIndex = 0
    private var fillCount = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = [Float](repeating: 0, count: capacity)
    }

    func write(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        for sample in samples {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            if fillCount == capacity {
                readIndex = (readIndex + 1) % capacity
            } else {
                fillCount += 1
            }
        }
    }

    @discardableResult
    func read(into dst: UnsafeMutablePointer<Float>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let available = min(count, fillCount)
        for i in 0..<available {
            dst[i] = storage[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        fillCount -= available
        if available < count {
            for i in available..<count { dst[i] = 0 }
        }
        return available
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return fillCount
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        readIndex = 0
        writeIndex = 0
        fillCount = 0
    }
}

// MARK: - BlackHole 输出桥

final class BlackHoleBridge: @unchecked Sendable {

    private let deviceNamePrefix: String
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let ring: RingBuffer
    private var sourceSampleRate: Double = 16000
    private var isRunning = false

    private let stateQueue = DispatchQueue(label: "com.myremote.blackhole.state")
    private let workQueue = DispatchQueue(label: "com.myremote.blackhole.work", qos: .userInitiated)
    private var generation = 0

    init(deviceNamePrefix: String) {
        self.deviceNamePrefix = deviceNamePrefix
        self.ring = RingBuffer(capacity: 16000 * 4)
    }

    var isDeviceAvailable: Bool {
        AudioDevices.findOutputDevice(namePrefix: deviceNamePrefix) != nil
    }

    /// 引擎当前是否在跑（调试/自检用）。
    var isRunningNow: Bool {
        stateQueue.sync { isRunning }
    }

    /// 语音流开始：清空缓冲并启动引擎（若已在运行则复用）。
    func streamStarted(sampleRate: Double) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.ring.clear()
            self.sourceSampleRate = sampleRate
            guard !self.isRunning else { return }
            do {
                try self.start()
                self.isRunning = true
            } catch {
                Log.error("BlackHole 输出启动失败: \(error.localizedDescription)")
            }
        }
    }

    func write(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        var floats = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            floats[i] = Float(samples[i]) / 32768.0
        }
        ring.write(floats)
    }

    /// 语音流结束：排空缓冲后停机；若期间又来了新流则取消本次停机。
    func streamStopped() {
        stateQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.isRunning = false
            self.generation += 1
            let gen = self.generation

            self.workQueue.async { [weak self] in
                guard let self else { return }
                if self.ring.count > 0 {
                    let deadline = Date().addingTimeInterval(2.0)
                    while self.ring.count > 0 && Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                self.stateQueue.async { [weak self] in
                    guard let self, gen == self.generation else { return }
                    self.engine.stop()
                    if let node = self.sourceNode {
                        self.engine.detach(node)
                        self.sourceNode = nil
                    }
                }
            }
        }
    }

    /// 立即停机（用户关闭共享时）。
    func stopNow() {
        stateQueue.sync {
            generation += 1
            isRunning = false
            ring.clear()
            engine.stop()
            if let node = sourceNode {
                engine.detach(node)
                sourceNode = nil
            }
        }
    }

    // MARK: - 引擎

    private func start() throws {
        guard let deviceID = AudioDevices.findOutputDevice(namePrefix: deviceNamePrefix) else {
            throw NSError(domain: "BlackHole", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "找不到输出设备 \(deviceNamePrefix)",
            ])
        }
        try bindOutputDevice(deviceID)

        let output = engine.outputNode
        let outputFormat = output.outputFormat(forBus: 0)
        let outputSampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48000

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "BlackHole", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "无法创建源格式",
            ])
        }

        let ringRef = ring
        let node = AVAudioSourceNode(format: sourceFormat) { _, _, frameCount, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)
            if let data = abl[0].mData {
                let pointer = data.assumingMemoryBound(to: Float.self)
                ringRef.read(into: pointer, count: count)
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)

        let connectFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        )
        engine.connect(node, to: engine.mainMixerNode, format: connectFormat)

        do {
            try engine.start()
        } catch {
            engine.detach(node)
            sourceNode = nil
            throw error
        }
    }

    private func bindOutputDevice(_ deviceID: AudioObjectID) throws {
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw NSError(domain: "BlackHole", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "outputNode 无 audioUnit",
            ])
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard status == noErr else {
            throw NSError(domain: "BlackHole", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "绑定输出设备失败 (\(status))",
            ])
        }
    }
}
