import Foundation

/// 指令模式的一条规则：说出的短语 → 自动执行的动作。
///
/// 默认预置「打开大肥鱼」（启动 DeepSeek Harness）与「发送到『李白』会话」。
struct CommandRule: Codable, Equatable, Identifiable {

    enum MatchMode: String, Codable, CaseIterable {
        case contains
        case exact

        var label: String {
            switch self {
            case .contains: return "包含"
            case .exact: return "完全一致"
            }
        }
    }

    var id: String
    var name: String
    /// 触发短语（任一命中即可；匹配前会忽略大小写、空格与标点）。
    var phrases: [String]
    var action: CommandAction
    var matchMode: MatchMode
    var enabled: Bool

    init(id: String = UUID().uuidString,
         name: String = "",
         phrases: [String] = [],
         action: CommandAction = .openApp(bundleID: ""),
         matchMode: MatchMode = .contains,
         enabled: Bool = true) {
        self.id = id
        self.name = name
        self.phrases = phrases
        self.action = action
        self.matchMode = matchMode
        self.enabled = enabled
    }

    /// 是否「发送到 DSH 会话」动作（配置迁移用）。
    var isSendToDSH: Bool {
        if case .sendToDSH = action { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, phrases, action, matchMode, enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        phrases = try container.decodeIfPresent([String].self, forKey: .phrases) ?? []
        action = try container.decodeIfPresent(CommandAction.self, forKey: .action) ?? .openApp(bundleID: "")
        matchMode = try container.decodeIfPresent(MatchMode.self, forKey: .matchMode) ?? .contains
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// 预置指令：打开 DSH；以及「我要听李白」→ 发送到「李白」会话。
    static var defaults: [CommandRule] {
        [
            CommandRule(
                name: "打开大肥鱼",
                phrases: [
                    "打开dsh", "启动dsh", "切换到dsh", "dsh", "deepseekharness",
                    "打开deepseek", "打开大肥鱼", "打开大飞云", "打开大飞鱼",
                ],
                action: .openApp(bundleID: "com.deepseek.dsh")
            ),
            CommandRule(
                name: "发送到「李白」会话",
                phrases: ["我要听李白", "听李白", "播放李白"],
                action: .sendToDSH(sessionId: "", sessionTitle: "李白", message: "{{text}}")
            ),
        ]
    }
}

/// 指令命中的动作。
enum CommandAction: Equatable, Hashable {
    /// 打开应用；已在运行则切到前台。
    case openApp(bundleID: String)
    /// 打开网址或文件路径。
    case openURL(String)
    /// 运行 shell 命令（用户自己在设置里配置）。
    case runShell(String)
    /// 把识别文本发送给本机 DSH 的一个会话（sessionId 为空时按标题解析）。
    case sendToDSH(sessionId: String, sessionTitle: String, message: String)

    var summary: String {
        switch self {
        case .openApp(let bundleID):
            return bundleID.isEmpty
                ? localized("打开应用（未配置）")
                : localized("打开应用 %@", bundleID)
        case .openURL(let value):
            return value.isEmpty ? localized("打开网址（未配置）") : localized("打开 %@", value)
        case .runShell(let command):
            return command.isEmpty ? localized("运行命令（未配置）") : localized("运行 %@", command)
        case .sendToDSH(_, let sessionTitle, let message):
            let target = sessionTitle.isEmpty ? localized("未命名会话") : sessionTitle
            let body = message.isEmpty ? localized("识别文本") : message
            return localized("发送到「%@」：%@", target, body)
        }
    }
}

extension CommandAction: Codable {

    private enum K: String, CodingKey { case type, bundleID, value, sessionId, sessionTitle, message }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: K.self)
        switch try container.decode(String.self, forKey: .type) {
        case "open_app":
            self = .openApp(bundleID: try container.decodeIfPresent(String.self, forKey: .bundleID) ?? "")
        case "open_url":
            self = .openURL(try container.decodeIfPresent(String.self, forKey: .value) ?? "")
        case "run_shell":
            self = .runShell(try container.decodeIfPresent(String.self, forKey: .value) ?? "")
        case "send_to_dsh":
            self = .sendToDSH(
                sessionId: try container.decodeIfPresent(String.self, forKey: .sessionId) ?? "",
                sessionTitle: try container.decodeIfPresent(String.self, forKey: .sessionTitle) ?? "",
                message: try container.decodeIfPresent(String.self, forKey: .message) ?? ""
            )
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "未知指令动作: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: K.self)
        switch self {
        case .openApp(let bundleID):
            try container.encode("open_app", forKey: .type)
            try container.encode(bundleID, forKey: .bundleID)
        case .openURL(let value):
            try container.encode("open_url", forKey: .type)
            try container.encode(value, forKey: .value)
        case .runShell(let command):
            try container.encode("run_shell", forKey: .type)
            try container.encode(command, forKey: .value)
        case .sendToDSH(let sessionId, let sessionTitle, let message):
            try container.encode("send_to_dsh", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(sessionTitle, forKey: .sessionTitle)
            try container.encode(message, forKey: .message)
        }
    }
}

/// 指令匹配：先把文本归一化（小写、去掉空格标点），再按规则顺序找第一个命中项。
enum CommandMatcher {

    static func normalize(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func matches(_ text: String, rule: CommandRule) -> Bool {
        let target = normalize(text)
        guard !target.isEmpty else { return false }
        for phrase in rule.phrases {
            let needle = normalize(phrase)
            guard !needle.isEmpty else { continue }
            switch rule.matchMode {
            case .contains where target.contains(needle):
                return true
            case .exact where target == needle:
                return true
            default:
                continue
            }
        }
        return false
    }

    static func firstMatch(_ text: String, rules: [CommandRule]) -> CommandRule? {
        rules.first { $0.enabled && matches(text, rule: $0) }
    }
}
