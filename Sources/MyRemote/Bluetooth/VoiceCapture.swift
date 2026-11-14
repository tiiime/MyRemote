import Foundation

/// 语音会话缓冲：ATVV 流开始 → 清空；音频帧 → 追加；流结束 → 交出整段 PCM。
/// 全部方法线程安全，回调切主线程。
final class VoiceCapture {

    private let lock = NSLock()
    private var samples: [Int16] = []
    private var active = false
    private let maxSamples = 16000 * 90   // 90 秒兜底，防异常流无限增长

    var onStart: (() -> Void)?
    var onFinish: ((_ samples: [Int16]) -> Void)?

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    func start() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        active = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onStart?() }
    }

    /// 录音期间的只读快照，用于实时预览识别。
    func sampleSnapshot() -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        return active ? samples : []
    }

    func append(_ newSamples: [Int16]) {
        guard !newSamples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard active, samples.count < maxSamples else { return }
        samples.append(contentsOf: newSamples)
    }

    func stop() {
        lock.lock()
        guard active else { lock.unlock(); return }
        active = false
        let snapshot = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onFinish?(snapshot) }
    }

    func cancel() {
        lock.lock()
        active = false
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
