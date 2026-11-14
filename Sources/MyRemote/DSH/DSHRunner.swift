import Foundation

/// CLI：查看/发送 DSH 会话消息。
///   MyRemote --list-dsh
///   MyRemote --send-dsh 李白 "我要听李白" [--execute]
///   MyRemote --send-dsh-id session-… "消息" [--execute]
enum DSHRunner {

    static func list() -> Bool {
        let sessions = DSHSessionStore.sessions()
        guard !sessions.isEmpty else {
            print("没有找到 DSH 会话（确认 ~/.dsh 存在且 DSH 用过）")
            return false
        }
        for session in sessions {
            let title = session.title.isEmpty ? "（未命名）" : session.title
            print("\(title) · \(session.workspaceName)  →  \(session.id)")
        }
        return true
    }

    static func send(title: String, message: String, execute: Bool) -> Bool {
        guard let session = DSHSessionStore.resolveSession(title: title) else {
            print("找不到标题为「\(title)」的 DSH 会话")
            return false
        }
        print("目标会话：\(session.title)（\(session.workspacePath)）")
        print("会话 ID：\(session.id)")
        return deliver(sessionId: session.id, message: message, execute: execute)
    }

    static func send(sessionId: String, message: String, execute: Bool) -> Bool {
        deliver(sessionId: sessionId, message: message, execute: execute)
    }

    private static func deliver(sessionId: String, message: String, execute: Bool) -> Bool {
        print("消息：\(message)")
        guard execute else {
            print("（仅解析；加 --execute 才会真正发送）")
            return true
        }

        var done = false
        var success = false
        DSHClient.shared.sendPrompt(sessionId: sessionId, text: message) { result in
            switch result {
            case .success:
                print("✓ 已发送")
                success = true
            case .failure(let error):
                print("✗ \(error.localizedDescription)")
            }
            done = true
        }
        while !done {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        return success
    }
}
