import Foundation
import AppKit

/// 执行指令动作。所有回调切主线程。
enum CommandRunner {

    typealias Completion = (Bool, String) -> Void

    static func execute(_ action: CommandAction, input: String,
                        completion: @escaping Completion) {
        switch action {
        case .openApp(let bundleID):
            openApp(bundleID: bundleID, completion: completion)
        case .openURL(let value):
            openURL(value, completion: completion)
        case .runShell(let command):
            runShell(command, completion: completion)
        case .sendToDSH(let sessionId, let sessionTitle, let message):
            sendToDSH(sessionId: sessionId, sessionTitle: sessionTitle,
                      message: message, input: input, completion: completion)
        }
    }

    /// 消息模板：空模板 = 直接发送识别文本；`{{text}}` 会被识别文本替换。
    static func renderMessage(template: String, input: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return input }
        return trimmed.replacingOccurrences(of: "{{text}}", with: input)
    }

    // MARK: - 打开应用（已在运行则切前台）

    static func openApp(bundleID: String, completion: @escaping Completion) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            completion(false, "指令未配置应用的 bundle id")
            return
        }

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            let ok = running.activate(options: [.activateIgnoringOtherApps])
            completion(ok, ok ? "已切换到 \(running.localizedName ?? id)" : "切换 \(id) 失败")
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            completion(false, "找不到应用：\(id)（未安装？）")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                if let error {
                    completion(false, "启动失败：\(error.localizedDescription)")
                } else {
                    completion(true, "已启动 \(app?.localizedName ?? id)")
                }
            }
        }
    }

    // MARK: - 打开网址 / 文件

    static func openURL(_ value: String, completion: @escaping Completion) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false, "指令未配置网址或路径")
            return
        }

        let url: URL
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        } else if let parsed = URL(string: trimmed), parsed.scheme != nil {
            url = parsed
        } else {
            url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }

        let ok = NSWorkspace.shared.open(url)
        completion(ok, ok ? "已打开 \(trimmed)" : "打不开 \(trimmed)")
    }

    // MARK: - 发送到 DSH 会话

    static func sendToDSH(sessionId: String, sessionTitle: String,
                          message: String, input: String,
                          completion: @escaping Completion) {
        let text = renderMessage(template: message, input: input)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            completion(false, "要发送的内容为空")
            return
        }

        var resolvedId = sessionId
        var resolvedTitle = sessionTitle
        if resolvedId.isEmpty {
            guard let session = DSHSessionStore.resolveSession(title: sessionTitle) else {
                completion(false, "找不到标题为「\(sessionTitle)」的 DSH 会话")
                return
            }
            resolvedId = session.id
            resolvedTitle = session.title
        }
        if resolvedTitle.isEmpty { resolvedTitle = resolvedId }

        DSHClient.shared.sendPrompt(sessionId: resolvedId, text: text) { result in
            switch result {
            case .success:
                completion(true, "已发送到「\(resolvedTitle)」")
            case .failure(let error):
                completion(false, error.localizedDescription)
            }
        }
    }

    // MARK: - Shell

    static func runShell(_ command: String, completion: @escaping Completion) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false, "指令未配置 shell 命令")
            return
        }
        // 不阻塞 App：后台拉起，结束再回调结果。
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", trimmed]
            let pipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = pipe

            // 持续排空 stderr，避免子进程写满管道阻塞。
            let lock = NSLock()
            var stderrData = Data()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                lock.lock()
                stderrData.append(chunk)
                if stderrData.count > 8192 { stderrData = stderrData.suffix(8192) }
                lock.unlock()
            }

            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                lock.lock()
                let data = stderrData
                lock.unlock()
                let stderr = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    if finished.terminationStatus == 0 {
                        completion(true, "命令已执行")
                    } else {
                        let detail = stderr.isEmpty ? "退出码 \(finished.terminationStatus)"
                                                    : String(stderr.suffix(160))
                        completion(false, "命令失败：\(detail)")
                    }
                }
            }
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    completion(false, "命令启动失败：\(error.localizedDescription)")
                }
            }
        }
    }
}
