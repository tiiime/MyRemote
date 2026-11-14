import Foundation

/// SenseVoice 模型下载与管理。
///
/// 文件放在 `~/Library/Application Support/MyRemote/Models/sensevoice/`：
///   - model.int8.onnx（约 230MB）
///   - tokens.txt
///
/// 优先 HuggingFace 主站，失败自动切镜像；大文件按 8 段并发下载（单连接带宽受限时
/// 仍能跑满），每段独立重试，最后按偏移拼装。
final class ModelManager {

    struct Spec {
        let name: String
        let minBytes: Int64
    }

    static let specs: [Spec] = [
        Spec(name: "model.int8.onnx", minBytes: 100_000_000),
        Spec(name: "tokens.txt", minBytes: 10_000),
    ]

    enum ModelError: LocalizedError {
        case downloadFailed(String)
        case incomplete(String, Int64, Int64)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let message): return "模型下载失败：\(message)"
            case .incomplete(let name, let actual, let expected):
                return "\(name) 大小异常（\(actual) < \(expected) 字节）"
            case .badResponse(let message): return "模型下载失败：\(message)"
            }
        }
    }

    let repository: String
    let mirror: String?
    let directory: URL
    private(set) var isDownloading = false

    init(repository: String, mirror: String?, directory: URL) {
        self.repository = repository
        self.mirror = mirror?.isEmpty == true ? nil : mirror
        self.directory = directory
    }

    var modelURL: URL { directory.appendingPathComponent("model.int8.onnx") }
    var tokensURL: URL { directory.appendingPathComponent("tokens.txt") }

    var isInstalled: Bool {
        Self.specs.allSatisfy { spec in
            let path = directory.appendingPathComponent(spec.name).path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? Int64 else { return false }
            return size >= spec.minBytes
        }
    }

    /// 下载缺失文件。progress: (0...1 总进度, 状态文案)。
    func install(progress: @escaping (Double, String) -> Void,
                 completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isDownloading else { return }
        isDownloading = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let missing = Self.specs.filter { spec in
            let path = directory.appendingPathComponent(spec.name).path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? Int64 else { return true }
            return size < spec.minBytes
        }

        guard !missing.isEmpty else {
            isDownloading = false
            completion(.success(()))
            return
        }

        DispatchQueue.global(qos: .utility).async {
            for (index, spec) in missing.enumerated() {
                let baseURLs = Self.baseURLs(repository: self.repository, mirror: self.mirror)
                let result = self.downloadFile(spec: spec, baseURLs: baseURLs,
                                               overallIndex: index, overallCount: missing.count,
                                               progress: progress)
                if case .failure(let error) = result {
                    self.isDownloading = false
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
            }
            self.isDownloading = false
            DispatchQueue.main.async { completion(.success(())) }
        }
    }

    // MARK: - 单文件

    private func downloadFile(spec: Spec, baseURLs: [URL],
                              overallIndex: Int, overallCount: Int,
                              progress: @escaping (Double, String) -> Void) -> Result<Void, Error> {
        let destination = directory.appendingPathComponent(spec.name)
        var lastError: Error = ModelError.downloadFailed("\(spec.name)：所有下载源均失败")

        // 每个源最多尝试两轮：网络抖动/分片停滞时给镜像一次重试机会。
        let attempts = baseURLs + baseURLs
        for (attempt, base) in attempts.enumerated() {
            let url = base.appendingPathComponent(spec.name)
            guard let size = Self.contentLength(of: url), size >= spec.minBytes else {
                lastError = ModelError.badResponse("\(url.host ?? "?") 未返回有效文件大小")
                Log.warn("下载源不可用：\(url.host ?? "?")（无法获取 Content-Length）")
                continue
            }

            Log.info("开始下载 \(spec.name) ← \(url.host ?? "?")（\(size) 字节，第 \(attempt + 1)/\(attempts.count) 次尝试）")
            let result = downloadChunks(url: url, size: size, destination: destination,
                                        chunkCount: size > 32_000_000 ? 8 : 1,
                                        progress: { written in
                let fileFraction = Double(written) / Double(size)
                let overall = (Double(overallIndex) + fileFraction) / Double(overallCount)
                let percent = Int(fileFraction * 100)
                progress(overall, "正在下载 \(spec.name) \(percent)%")
            })

            switch result {
            case .success:
                let actual = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
                if actual >= spec.minBytes {
                    Log.info("模型文件就绪: \(spec.name)")
                    return .success(())
                }
                lastError = ModelError.incomplete(spec.name, actual, spec.minBytes)
            case .failure(let error):
                lastError = error
                Log.warn("下载失败（\(url.host ?? "?")）：\(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: destination)
        }
        return .failure(lastError)
    }

    /// 同步等待分段下载结束（在后台队列调用）。
    private func downloadChunks(url: URL, size: Int64, destination: URL,
                                chunkCount: Int,
                                progress: @escaping (Int64) -> Void) -> Result<Void, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Void, Error> = .failure(ModelError.downloadFailed("下载中止"))
        let downloader = ParallelDownloader(url: url, totalSize: size, destination: destination,
                                            chunkCount: chunkCount, progress: progress) { result in
            outcome = result
            semaphore.signal()
        }
        downloader.start()
        semaphore.wait()
        return outcome
    }

    /// 调试用：用小文件验证「分段 Range 下载 + 拼装」逻辑。
    static func selfTestChunked(url: URL, size: Int64, chunks: Int,
                                destination: URL) -> Result<Void, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Void, Error> = .failure(ModelError.downloadFailed("未开始"))
        let downloader = ParallelDownloader(url: url, totalSize: size,
                                            destination: destination,
                                            chunkCount: chunks, progress: { _ in }) { result in
            outcome = result
            semaphore.signal()
        }
        downloader.start()
        semaphore.wait()
        return outcome
    }

    static func baseURLs(repository: String, mirror: String?) -> [URL] {
        var urls: [URL] = []
        if let primary = URL(string: "https://huggingface.co/\(repository)/resolve/main/") {
            urls.append(primary)
        }
        if let mirror, let url = URL(string: "\(mirror)/\(repository)/resolve/main/") {
            urls.append(url)
        }
        return urls
    }

    static func contentLengthForTest(_ url: URL) -> Int64? { contentLength(of: url) }

    private static func contentLength(of url: URL) -> Int64? {
        if let length = headLength(url) { return length }
        return rangeProbeLength(url)
    }

    /// HEAD 方式取 Content-Length。必须关闭压缩：否则文本文件会走 chunked、拿不到长度。
    private static func headLength(_ url: URL) -> Int64? {
        let semaphore = DispatchSemaphore(value: 0)
        var length: Int64?
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse,
               let value = http.value(forHTTPHeaderField: "Content-Length"),
               let parsed = Int64(value), parsed > 0 {
                length = parsed
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return length
    }

    /// 兜底：GET Range 0-0，从 Content-Range: bytes 0-0/TOTAL 读出总大小。
    private static func rangeProbeLength(_ url: URL) -> Int64? {
        let semaphore = DispatchSemaphore(value: 0)
        var length: Int64?
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse,
               let value = http.value(forHTTPHeaderField: "Content-Range"),
               let total = value.split(separator: "/").last,
               let parsed = Int64(total.trimmingCharacters(in: .whitespaces)) {
                length = parsed
            } else if let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      let value = http.value(forHTTPHeaderField: "Content-Length"),
                      let parsed = Int64(value) {
                length = parsed
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return length
    }
}

// MARK: - 分段并发下载

private final class ParallelDownloader {

    private let url: URL
    private let totalSize: Int64
    private let destination: URL
    private let chunkDir: URL
    private let progress: (Int64) -> Void
    private let completion: (Result<Void, Error>) -> Void
    private var chunks: [Chunk] = []
    private let lock = NSLock()
    private var finished = false
    private var lastActivity = Date()
    private var watchdog: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "com.myremote.download.watchdog")

    private struct Chunk {
        let start: Int64
        let end: Int64
        let file: URL
        var written: Int64 = 0
        var task: ChunkTask?
    }

    init(url: URL, totalSize: Int64, destination: URL, chunkCount: Int,
         progress: @escaping (Int64) -> Void,
         completion: @escaping (Result<Void, Error>) -> Void) {
        self.url = url
        self.totalSize = totalSize
        self.destination = destination
        self.chunkDir = destination.appendingPathExtension("chunks")
        self.progress = progress
        self.completion = completion
        self.chunkCount = max(1, chunkCount)
    }

    private let chunkCount: Int

    func start() {
        try? FileManager.default.removeItem(at: chunkDir)
        try? FileManager.default.createDirectory(at: chunkDir, withIntermediateDirectories: true)

        let count = Int64(chunkCount)
        let chunkSize = (totalSize + count - 1) / count
        for index in 0..<chunkCount {
            let start = Int64(index) * chunkSize
            guard start < totalSize else { break }
            let end = min(start + chunkSize - 1, totalSize - 1)
            let file = chunkDir.appendingPathComponent(String(format: "chunk_%02d", index))
            var chunk = Chunk(start: start, end: end, file: file)
            let task = ChunkTask(start: start, end: end, output: file,
                                 allowFullResponse: chunkCount == 1 && start == 0)
            task.onProgress = { [weak self] written in
                self?.chunkProgress(index: index, written: written)
            }
            task.onFinish = { [weak self] error in
                self?.chunkFinished(index: index, error: error)
            }
            chunk.task = task
            chunks.append(chunk)
            task.start(url: url)
        }

        lastActivity = Date()
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 30, repeating: 15)
        timer.setEventHandler { [weak self] in self?.checkStall() }
        timer.resume()
        watchdog = timer
    }

    /// 某个分片超过 90 秒没有任何字节写入 → 判定网络停滞，让上层换源重试。
    private func checkStall() {
        lock.lock()
        let idle = Date().timeIntervalSince(lastActivity)
        let done = finished
        lock.unlock()
        guard !done, idle > 90 else { return }
        fail(NSError(domain: "MyRemote", code: 5,
                     userInfo: [NSLocalizedDescriptionKey: "下载停滞超过 90 秒"]))
    }

    private func fail(_ error: Error) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let tasks = chunks.compactMap(\.task)
        lock.unlock()
        watchdog?.cancel()
        watchdog = nil
        tasks.forEach { $0.cancel() }
        cleanup()
        completion(.failure(error))
    }

    private func chunkProgress(index: Int, written: Int64) {
        lock.lock()
        guard index < chunks.count, !finished else { lock.unlock(); return }
        chunks[index].written = written
        lastActivity = Date()
        let total = chunks.reduce(0) { $0 + $1.written }
        lock.unlock()
        progress(total)
    }

    private func chunkFinished(index: Int, error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let chunk = chunks[index]
        let expected = chunk.end - chunk.start + 1
        let actual = (try? FileManager.default.attributesOfItem(atPath: chunk.file.path)[.size] as? Int64) ?? 0
        let failure = error ?? (actual == expected ? nil : NSError(
            domain: "MyRemote", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "分片 \(index) 大小异常（\(actual)/\(expected)）"]))
        if let failure {
            lock.unlock()
            fail(failure)
            return
        }
        chunks[index].written = expected
        let allDone = chunks.allSatisfy { $0.written >= ($0.end - $0.start + 1) && $0.task != nil }
        lock.unlock()
        if allDone { assemble() }
    }

    private func assemble() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        watchdog?.cancel()
        watchdog = nil
        let snapshot = chunks
        lock.unlock()

        do {
            try? FileManager.default.removeItem(at: destination)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let output = try FileHandle(forWritingTo: destination)
            for chunk in snapshot {
                let data = try Data(contentsOf: chunk.file, options: .mappedIfSafe)
                output.write(data)
            }
            try output.close()
            let actual = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            guard actual == totalSize else {
                cleanup()
                completion(.failure(NSError(domain: "MyRemote", code: 4,
                                            userInfo: [NSLocalizedDescriptionKey:
                                                        "合并后大小异常（\(actual)/\(totalSize)）"])))
                return
            }
            cleanup()
            completion(.success(()))
        } catch {
            cleanup()
            completion(.failure(error))
        }
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: chunkDir)
    }
}

private final class ChunkTask: NSObject, URLSessionDownloadDelegate {

    private let start: Int64
    private let end: Int64
    private let output: URL
    private var session: URLSession?
    private var pendingError: Error?

    var onProgress: ((Int64) -> Void)?
    var onFinish: ((Error?) -> Void)?

    /// allowFullResponse：整文件单分片时服务器忽略 Range 返回 200 也接受。
    private let allowFullResponse: Bool

    init(start: Int64, end: Int64, output: URL, allowFullResponse: Bool) {
        self.start = start
        self.end = end
        self.output = output
        self.allowFullResponse = allowFullResponse
    }

    func start(url: URL) {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        // 关闭压缩：Range 的字节偏移必须对应原始文件内容。
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = 120
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 7200
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: request).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if let http = downloadTask.response as? HTTPURLResponse,
           http.statusCode != 206, !allowFullResponse {
            pendingError = NSError(domain: "MyRemote", code: 6,
                                   userInfo: [NSLocalizedDescriptionKey:
                                               "服务器未按 Range 返回（HTTP \(http.statusCode)）"])
            session.invalidateAndCancel()
            return
        }
        onProgress?(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: location, to: output)
        } catch {
            pendingError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let http = task.response as? HTTPURLResponse, http.statusCode != 206 && http.statusCode != 200 {
            pendingError = NSError(domain: "MyRemote", code: http.statusCode,
                                   userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        onFinish?(pendingError ?? error)
    }
}
