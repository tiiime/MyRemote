import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 给按键配置一条「指令动作」：打开应用 / 网页 / 运行 Shell / 发送到 DSH。
/// 和指令规则使用同一套 CommandAction 与执行器。
struct KeyCommandEditorView: View {

    let initial: CommandAction?
    let onClose: () -> Void
    let onSave: (CommandAction) -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case openApp
        case openURL
        case runShell
        case sendToDSH

        var id: String { rawValue }

        var label: String {
            switch self {
            case .openApp: return localized("打开应用")
            case .openURL: return localized("打开网页")
            case .runShell: return localized("运行 Shell")
            case .sendToDSH: return localized("发送到 DSH")
            }
        }
    }

    @State private var kind: Kind
    @State private var target: String
    @State private var sessionId: String
    @State private var sessionTitle: String
    @State private var message: String
    @State private var sessions: [DSHSessionInfo] = []

    init(initial: CommandAction?,
         onClose: @escaping () -> Void,
         onSave: @escaping (CommandAction) -> Void) {
        self.initial = initial
        self.onClose = onClose
        self.onSave = onSave

        var kind = Kind.openURL
        var target = ""
        var sessionId = ""
        var sessionTitle = ""
        var message = ""
        switch initial {
        case .openApp(let bundleID):
            kind = .openApp
            target = bundleID
        case .openURL(let value):
            kind = .openURL
            target = value
        case .runShell(let command):
            kind = .runShell
            target = command
        case .sendToDSH(let id, let title, let body):
            kind = .sendToDSH
            sessionId = id
            sessionTitle = title
            message = body
        case nil:
            break
        }
        _kind = State(initialValue: kind)
        _target = State(initialValue: target)
        _sessionId = State(initialValue: sessionId)
        _sessionTitle = State(initialValue: sessionTitle)
        _message = State(initialValue: message)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(initial == nil ? localized("设置指令动作") : localized("编辑指令动作"))
                .font(.duo(20, .heavy))
                .foregroundStyle(Duo.eel)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("动作类型")
                Picker("", selection: $kind) {
                    ForEach(Kind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(Duo.swan)

            actionFields

            HStack {
                Spacer()
                Button("取消", action: onClose)
                    .buttonStyle(DuoSecondaryButtonStyle())
                Button("保存") { save() }
                    .buttonStyle(DuoPrimaryButtonStyle())
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Duo.white)
        .onAppear { sessions = DSHSessionStore.sessions() }
    }

    @ViewBuilder
    private var actionFields: some View {
        switch kind {
        case .openApp:
            fieldLabel("Bundle ID")
            HStack(spacing: 8) {
                DuoTextField(placeholder: "例如 com.deepseek.dsh", text: $target)
                Button("选择…") { chooseApplication() }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 40))
            }
            Text("已在运行会切到前台").font(.duo(9, .medium)).foregroundStyle(Duo.hare)

        case .openURL:
            fieldLabel("网址或文件路径")
            HStack(spacing: 8) {
                DuoTextField(placeholder: "https://… 或 /Applications/xxx.app", text: $target)
                Button("选择…") { chooseFile() }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 40))
            }

        case .runShell:
            fieldLabel("Shell 命令")
            TextEditor(text: $target)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Duo.eel)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 96)
                .background(RoundedRectangle(cornerRadius: 10).fill(Duo.polar))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Duo.swan, lineWidth: 1.5)
                )
            Text("以 /bin/zsh -lc 执行，请只配置可信命令。按键触发时没有语音文本，命令会按原样执行。")
                .font(.duo(9, .medium))
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
            fieldLabel("固定消息")
            DuoTextField(placeholder: "按键触发时发送到该会话的内容", text: $message)
            Text("按键没有语音识别文本，这里需要填写固定消息。")
                .font(.duo(9, .medium))
                .foregroundStyle(Duo.hare)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.duo(11, .bold))
            .foregroundStyle(Duo.wolf)
    }

    private var canSave: Bool {
        switch kind {
        case .openApp, .openURL, .runShell:
            return !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sendToDSH:
            let hasSession = !sessionId.isEmpty
                || !sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasSession && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        let value = target.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .openApp:
            onSave(.openApp(bundleID: value))
        case .openURL:
            onSave(.openURL(value))
        case .runShell:
            onSave(.runShell(value))
        case .sendToDSH:
            onSave(.sendToDSH(
                sessionId: sessionId,
                sessionTitle: sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                message: message
            ))
        }
        onClose()
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
        target = Bundle(url: url)?.bundleIdentifier ?? url.path
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        target = url.path
    }
}
