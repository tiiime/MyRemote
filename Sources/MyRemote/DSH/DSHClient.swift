import Foundation

/// 通过本机 HTTP 接口向运行中的 DSH 发送 prompt。
///
/// 流程：发现 DSH Web 端口 → 用本机凭据签浏览器 Cookie → `POST /api/session/prompt`。
/// 全部数据都只在 127.0.0.1 上传输。
final class DSHClient {

    static let shared = DSHClient()

    enum ClientError: LocalizedError {
        case notRunning
        case noCredential
        case unauthorized
        case rpc(code: String, message: String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "没找到运行中的 DeepSeek Harness（请先打开 DSH）"
            case .noCredential:
                return "读不到 DSH 的本地凭据（~/.dsh/.credentials.yaml）"
            case .unauthorized:
                return "DSH 拒绝了本机凭据（Cookie 认证失败）"
            case .rpc(let code, let message):
                return "DSH 返回错误：\(code) \(message)"
            case .badResponse(let text):
                return "DSH 响应异常：\(text)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.myremote.dsh", qos: .userInitiated)
    private var cachedBase: URL?

    /// 清掉端口缓存（DSH 重启后端口可能变化）。
    func resetCache() {
        queue.sync { cachedBase = nil }
    }

    // MARK: - 发送

    /// 发送一条文本 prompt 到指定会话。回调在主线程。
    func sendPrompt(sessionId: String, text: String,
                    completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let requestArgs: [String: Any] = [
                "requestId": UUID().uuidString,
                "sessionId": sessionId,
                "mode": "queue",
                "content": [["type": "text", "text": text]],
            ]
            do {
                _ = try self.postWithRetry(endpoint: "session/prompt",
                                           argName: "request", args: requestArgs)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// 发送一条原始 RPC 请求（调试用）。
    func call(endpoint: String, argName: String, args: [String: Any],
              completion: @escaping (Result<Any, Error>) -> Void) {
        queue.async {
            do {
                let base = try self.baseURLLocked()
                let authority = self.authority(for: base)
                guard let cookie = DSHCredential.browserCookie(authority: authority) else {
                    throw ClientError.noCredential
                }
                let value = try self.postWithRetry(endpoint: endpoint,
                                                   argName: argName, args: args)
                DispatchQueue.main.async { completion(.success(value ?? NSNull())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// 端口缓存失效（DSH 重启换端口）时自动重新发现并重试一次。
    private func postWithRetry(endpoint: String, argName: String,
                               args: [String: Any]) throws -> Any? {
        do {
            return try postOnce(endpoint: endpoint, argName: argName, args: args)
        } catch let error as URLError where [.cannotConnectToHost, .networkConnectionLost,
                                             .timedOut, .cannotFindHost].contains(error.code) {
            cachedBase = nil
            return try postOnce(endpoint: endpoint, argName: argName, args: args)
        }
    }

    private func postOnce(endpoint: String, argName: String,
                          args: [String: Any]) throws -> Any? {
        let base = try baseURLLocked()
        let authority = self.authority(for: base)
        guard let cookie = DSHCredential.browserCookie(authority: authority) else {
            throw ClientError.noCredential
        }
        return try post(base: base, cookie: cookie,
                        endpoint: endpoint, argName: argName, args: args)
    }

    // MARK: - 端口发现

    private func baseURLLocked() throws -> URL {
        if let cachedBase { return cachedBase }
        if let env = ProcessInfo.processInfo.environment["MYREMOTE_DSH_URL"],
           let url = URL(string: env), url.port != nil {
            cachedBase = url
            return url
        }
        if let env = ProcessInfo.processInfo.environment["DSH_WEB_URL"],
           let url = URL(string: env), url.port != nil {
            cachedBase = url
            return url
        }
        for port in listeningPorts() {
            guard let url = URL(string: "http://127.0.0.1:\(port)") else { continue }
            if probe(url) {
                cachedBase = url
                return url
            }
        }
        throw ClientError.notRunning
    }

    private func authority(for base: URL) -> String {
        "\(base.host ?? "127.0.0.1"):\(base.port ?? 80)"
    }

    /// 从 lsof 里找 DSH 进程监听的 127.0.0.1 端口，再用 401 文案确认是 DSH Web。
    private func listeningPorts() -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var ports: [Int] = []
        for line in text.split(separator: "\n") {
            let lower = line.lowercased()
            guard lower.contains("deepseek") || lower.contains("dsh") else { continue }
            guard let range = line.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression) else { continue }
            let token = line[range]
            if let port = Int(token.split(separator: ":").last ?? "") {
                if !ports.contains(port) { ports.append(port) }
            }
        }
        return ports
    }

    private func probe(_ base: URL) -> Bool {
        var request = URLRequest(url: base)
        request.timeoutInterval = 2
        let semaphore = DispatchSemaphore(value: 0)
        var matched = false

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 401,
                  let data, let text = String(data: data, encoding: .utf8) else { return }
            matched = text.contains("dsh web authentication required")
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        return matched
    }

    // MARK: - RPC

    private func post(base: URL, cookie: String, endpoint: String,
                      argName: String, args: [String: Any]) throws -> Any? {
        guard let url = URL(string: "\(base.absoluteString)/api/\(endpoint)") else {
            throw ClientError.badResponse("无效地址")
        }
        let rpcId = UUID().uuidString
        let envelope: [String: Any] = [
            "type": "client-request",
            "rpcId": rpcId,
            "method": endpoint,
            "payload": ["args": [argName: args]],
        ]
        let body = try JSONSerialization.data(withJSONObject: envelope)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Any?, Error> = .failure(ClientError.badResponse("无响应"))

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse else {
                outcome = .failure(ClientError.badResponse("无 HTTP 响应"))
                return
            }
            if http.statusCode == 401 {
                outcome = .failure(ClientError.unauthorized)
                return
            }
            guard http.statusCode == 200, let data else {
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                outcome = .failure(ClientError.badResponse("HTTP \(http.statusCode) \(text.prefix(160))"))
                return
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = root["result"] as? [String: Any] else {
                outcome = .failure(ClientError.badResponse("不是 RPC 响应"))
                return
            }
            let ok = result["ok"] as? Bool ?? false
            if ok {
                outcome = .success(result["value"])
            } else if let error = result["error"] as? [String: Any] {
                outcome = .failure(ClientError.rpc(code: error["code"] as? String ?? "unknown",
                                                   message: error["message"] as? String ?? ""))
            } else {
                outcome = .failure(ClientError.badResponse("缺少 result"))
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 20)

        switch outcome {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}
