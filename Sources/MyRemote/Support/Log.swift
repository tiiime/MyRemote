import Foundation

/// 统一日志：stderr + 文件 + 内存环形缓冲（设置窗口实时显示）。
///
/// 隐私相关的约定：
/// - 文件权限固定 0600，只有当前用户能读；
/// - 超过 1MB 自动轮转成 MyRemote.log.1（只保留一份）；
/// - 识别文本默认不落盘，见 AppServices 里的 logTranscripts 开关。
enum Log {

    static let fileURL: URL = {
        // 自检/测试可以指到临时目录，避免动真实的 ~/Library/Logs。
        if let override = ProcessInfo.processInfo.environment["MYREMOTE_LOG_DIR"], !override.isEmpty {
            try? FileManager.default.createDirectory(atPath: override, withIntermediateDirectories: true)
            return URL(fileURLWithPath: override).appendingPathComponent("MyRemote.log")
        }
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MyRemote.log")
    }()

    /// 轮转阈值。
    private static let maxBytes: UInt64 = 1_000_000

    private static let lock = NSLock()
    private static var ring: [String] = []
    private static var fileHandle: FileHandle?

    /// 日志行回调（主线程触发；设置窗口订阅）。
    static var onLine: ((String) -> Void)?

    static func ringLines() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return ring
    }

    static func info(_ message: String) { write("INFO", message) }
    static func warn(_ message: String) { write("WARN", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "[\(timestamp())] [\(level)] \(message)"
        lock.lock()
        ring.append(line)
        if ring.count > 400 { ring.removeFirst(ring.count - 400) }
        let callback = onLine
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
        appendLocked(line + "\n")
        lock.unlock()

        if let callback {
            DispatchQueue.main.async { callback(line) }
        }
    }

    // MARK: - 文件

    private static func appendLocked(_ text: String) {
        if fileHandle == nil { openLocked() }
        rotateIfNeededLocked()
        fileHandle?.write(Data(text.utf8))
    }

    private static func openLocked() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil,
                                           attributes: [.posixPermissions: 0o600])
        }
        // 旧版本建的日志可能是 0644，顺手收紧。
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: fileURL.path)
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
    }

    private static func rotateIfNeededLocked() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes?[.size] as? UInt64, size > maxBytes else { return }
        try? fileHandle?.close()
        fileHandle = nil
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("MyRemote.log.1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
        fileHandle = try? FileHandle(forWritingTo: fileURL)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func timestamp() -> String { formatter.string(from: Date()) }
}
