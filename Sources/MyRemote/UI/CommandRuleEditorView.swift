import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 新建 / 编辑一条指令规则（左右双栏，避免在桌面端出现长滚动）。
struct CommandRuleEditorView: View {

    enum ActionKind: String, CaseIterable, Identifiable {
        case openApp
        case openURL
        case runShell
        case sendToDSH

        var id: String { rawValue }

        var label: String {
            switch self {
            case .openApp: return localized("打开应用")
            case .openURL: return localized("打开网址")
            case .runShell: return localized("运行命令")
            case .sendToDSH: return localized("发送到 DSH")
            }
        }

        var icon: String {
            switch self {
            case .openApp: return "macwindow"
            case .openURL: return "link"
            case .runShell: return "terminal.fill"
            case .sendToDSH: return "sparkles"
            }
        }
    }

    private let original: CommandRule
    private let onSave: (CommandRule) -> Void
    private let onCancel: () -> Void

    @State private var name: String
    @State private var phrasesText: String
    @State private var matchMode: CommandRule.MatchMode
    @State private var actionKind: ActionKind
    @State private var target: String
    @State private var sessionId: String
    @State private var sessionTitle: String
    @State private var dshMessage: String
    @State private var sessions: [DSHSessionInfo]

    init(rule: CommandRule,
         onSave: @escaping (CommandRule) -> Void,
         onCancel: @escaping () -> Void) {
        self.original = rule
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: rule.name)
        _phrasesText = State(initialValue: rule.phrases.joined(separator: "\n"))
        _matchMode = State(initialValue: rule.matchMode)
        _target = State(initialValue: "")
        _sessionId = State(initialValue: "")
        _sessionTitle = State(initialValue: "")
        _dshMessage = State(initialValue: "")
        _sessions = State(initialValue: DSHSessionStore.sessions())
        switch rule.action {
        case .openApp(let bundleID):
            _actionKind = State(initialValue: .openApp)
            _target = State(initialValue: bundleID)
        case .openURL(let value):
            _actionKind = State(initialValue: .openURL)
            _target = State(initialValue: value)
        case .runShell(let command):
            _actionKind = State(initialValue: .runShell)
            _target = State(initialValue: command)
        case .sendToDSH(let sessionId, let sessionTitle, let message):
            _actionKind = State(initialValue: .sendToDSH)
            _sessionId = State(initialValue: sessionId)
            _sessionTitle = State(initialValue: sessionTitle)
            _dshMessage = State(initialValue: message)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Duo.swan)
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    basicCard
                        .frame(maxWidth: .infinity, alignment: .top)
                    actionCard
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(20)
            }
            .scrollIndicators(.never)
            Divider().overlay(Duo.swan)
            footer
        }
        .frame(width: 900, height: 620)
        .background(Duo.polar)
    }

    // MARK: - 头部 / 底部

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Duo.seaSponge)
                    .frame(width: 40, height: 40)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Duo.treeFrog)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(original.name.isEmpty ? localized("新建指令") : localized("编辑指令"))
                    .font(.duo(20, .heavy))
                    .foregroundStyle(Duo.eel)
                Text("说出的短语命中后，自动执行动作")
                    .font(.duo(11, .medium))
                    .foregroundStyle(Duo.wolf)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Duo.wolf)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Duo.polar))
                    .overlay(Circle().strokeBorder(Duo.swan, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Duo.white)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("取消", action: onCancel)
                .buttonStyle(DuoSecondaryButtonStyle())
            Button("保存指令", action: save)
                .buttonStyle(DuoPrimaryButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Duo.white)
    }

    // MARK: - 左栏：指令

    private var basicCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "指令", icon: "text.quote", tint: Duo.eel)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("名称（可选）")
                DuoTextField(placeholder: "例如：打开 DeepSeek Harness", text: $name)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("触发短语（每行一个）")
                TextEditor(text: $phrasesText)
                    .font(.duo(13, .medium))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Duo.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Duo.swan, lineWidth: 2)
                    )
                Text("匹配时忽略大小写、空格与标点")
                    .font(.duo(10, .medium))
                    .foregroundStyle(Duo.hare)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("匹配方式")
                HStack(spacing: 8) {
                    ForEach(CommandRule.MatchMode.allCases, id: \.self) { mode in
                        ChoicePill(title: mode.label,
                                   selected: matchMode == mode,
                                   tint: Duo.treeFrog,
                                   background: Duo.seaSponge) {
                            matchMode = mode
                        }
                    }
                }
            }
        }
        .duoCard(padding: 18)
    }

    // MARK: - 右栏：动作

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "执行动作", icon: "play.circle.fill", tint: Duo.macaw)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ActionKind.allCases) { kind in
                    Button {
                        actionKind = kind
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 13, weight: .bold))
                            Text(kind.label)
                                .font(.duo(11, .heavy))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(actionKind == kind ? style(for: kind).tint : Duo.wolf)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(actionKind == kind ? style(for: kind).background : Duo.polar)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(actionKind == kind ? style(for: kind).tint.opacity(0.55) : Duo.swan,
                                              lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            actionFields
        }
        .duoCard(padding: 18)
    }

    private func style(for kind: ActionKind) -> CommandActionStyle {
        switch kind {
        case .openApp: return commandActionStyle(.openApp(bundleID: ""))
        case .openURL: return commandActionStyle(.openURL(""))
        case .runShell: return commandActionStyle(.runShell(""))
        case .sendToDSH: return commandActionStyle(.sendToDSH(sessionId: "", sessionTitle: "", message: ""))
        }
    }

    @ViewBuilder
    private var actionFields: some View {
        switch actionKind {
        case .openApp:
            fieldLabel("Bundle ID")
            HStack(spacing: 8) {
                DuoTextField(placeholder: "例如 com.deepseek.dsh", text: $target)
                Button("选择…") { chooseApplication() }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 40))
            }
        case .openURL:
            fieldLabel("网址或文件路径")
            DuoTextField(placeholder: "https://… 或 /Applications/xxx.app", text: $target)
        case .runShell:
            fieldLabel("Shell 命令")
            DuoTextField(placeholder: "例如 open -a \"DeepSeek Harness\"",
                         text: $target, monospaced: true)
            Text("以 /bin/zsh -lc 执行；请只配置可信命令")
                .font(.duo(10, .medium))
                .foregroundStyle(Duo.hare)
        case .sendToDSH:
            fieldLabel("会话")
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { sessionId },
                    set: { newValue in
                        sessionId = newValue
                        if let session = sessions.first(where: { $0.id == newValue }) {
                            sessionTitle = session.title
                        }
                    }
                )) {
                    Text(sessionTitle.isEmpty ? localized("按标题解析…") : localized("按标题：%@", sessionTitle)).tag("")
                    ForEach(sessions) { session in
                        Text(session.label).tag(session.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("刷新") { sessions = DSHSessionStore.sessions() }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 40))
            }
            if sessionId.isEmpty {
                fieldLabel("会话标题")
                DuoTextField(placeholder: "例如 李白；同名优先 MyRemote 工作区", text: $sessionTitle)
            }
            fieldLabel("消息")
            DuoTextField(placeholder: "默认发送识别文本；可用 {{text}} 引用", text: $dshMessage)
            Text("通过本机 DSH 接口投递，数据不出本机")
                .font(.duo(10, .medium))
                .foregroundStyle(Duo.hare)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.duo(11, .bold))
            .foregroundStyle(Duo.wolf)
    }

    // MARK: - 行为

    private var canSave: Bool {
        let hasPhrase = phrasesText.split(whereSeparator: \.isNewline)
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasPhrase else { return false }
        switch actionKind {
        case .sendToDSH:
            return !sessionId.isEmpty
                || !sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let bundleID = Bundle(url: url)?.bundleIdentifier {
            target = bundleID
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        } else {
            target = url.path
        }
    }

    private func save() {
        let phrases = phrasesText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? (phrases.first ?? "未命名指令") : trimmedName

        let action: CommandAction
        switch actionKind {
        case .openApp:
            action = .openApp(bundleID: target.trimmingCharacters(in: .whitespacesAndNewlines))
        case .openURL:
            action = .openURL(target.trimmingCharacters(in: .whitespacesAndNewlines))
        case .runShell:
            action = .runShell(target.trimmingCharacters(in: .whitespacesAndNewlines))
        case .sendToDSH:
            action = .sendToDSH(sessionId: sessionId,
                                sessionTitle: sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                message: dshMessage)
        }

        onSave(CommandRule(id: original.id, name: resolvedName, phrases: phrases,
                           action: action, matchMode: matchMode, enabled: original.enabled))
    }
}

// MARK: - 选择胶囊

struct ChoicePill: View {
    let title: String
    let selected: Bool
    var tint: Color = Duo.treeFrog
    var background: Color = Duo.seaSponge
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.duo(12, .heavy))
                .foregroundStyle(selected ? tint : Duo.wolf)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? background : Duo.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? tint.opacity(0.55) : Duo.swan, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}
