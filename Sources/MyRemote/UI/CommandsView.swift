import SwiftUI
import AppKit

// MARK: - 动作外观

struct CommandActionStyle {
    let icon: String
    let tint: Color
    let background: Color
    let label: String
}

func commandActionStyle(_ action: CommandAction) -> CommandActionStyle {
    switch action {
    case .openApp:
        return CommandActionStyle(icon: "macwindow", tint: Duo.treeFrog,
                                  background: Duo.seaSponge, label: "打开应用")
    case .openURL:
        return CommandActionStyle(icon: "link", tint: Duo.whale,
                                  background: Duo.iguana, label: "打开网址")
    case .runShell:
        return CommandActionStyle(icon: "terminal.fill", tint: Duo.fox,
                                  background: Duo.beeLight, label: "运行命令")
    case .sendToDSH:
        return CommandActionStyle(icon: "sparkles", tint: Duo.lily,
                                  background: Duo.beetleLight, label: "发送到 DSH")
    }
}

// MARK: - 指令页

struct CommandsView: View {

    @ObservedObject var model: SettingsModel
    @State private var editingRule: CommandRule?

    var body: some View {
        VStack(spacing: 16) {
            summaryBar

            ForEach(Array(model.config.commandRules.enumerated()), id: \.element.id) { index, rule in
                CommandRuleCard(model: model,
                                rule: rule,
                                index: index,
                                total: model.config.commandRules.count,
                                edit: { editingRule = rule })
            }

            if model.config.commandRules.isEmpty {
                DuoEmptyState(icon: "bolt.slash.fill",
                              title: "还没有指令",
                              message: "添加一条指令，例如说「打开 dsh」时启动 DeepSeek Harness。",
                              actionTitle: "添加第一条指令") {
                    editingRule = CommandRule()
                }
            }

            Button {
                editingRule = CommandRule()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("添加指令")
                }
            }
            .buttonStyle(DuoPrimaryButtonStyle(expand: true))
            .padding(.top, 4)
        }
        .sheet(item: $editingRule) { rule in
            CommandRuleEditorView(rule: rule) { saved in
                model.upsertCommand(saved)
                editingRule = nil
            } onCancel: {
                editingRule = nil
            }
        }
    }

    private var summaryBar: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                DuoSectionLabel(text: "匹配规则")
                Text(localized("%lld 条指令 · 按顺序第一个命中生效", model.config.commandRules.count))
                    .font(.duo(13, .medium))
                    .foregroundStyle(Duo.wolf)
            }
            Spacer()
            DuoChip(text: model.snapshot.voiceMode == .command ? "命令模式运行中" : "命令模式未激活",
                    color: model.snapshot.voiceMode == .command ? Duo.treeFrog : Duo.wolf,
                    background: model.snapshot.voiceMode == .command ? Duo.seaSponge : Duo.polar,
                    icon: "bolt.fill")
        }
        .duoCard(padding: 16)
    }
}

// MARK: - 规则卡

struct CommandRuleCard: View {

    @ObservedObject var model: SettingsModel
    let rule: CommandRule
    let index: Int
    let total: Int
    var edit: () -> Void

    private var style: CommandActionStyle { commandActionStyle(rule.action) }

    private func actionSummary(_ action: CommandAction) -> String {
        if case .openApp(let bundleID) = action,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return localized("打开应用 %@", url.deletingPathExtension().lastPathComponent)
        }
        return action.summary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(style.background)
                    .frame(width: 46, height: 46)
                Image(systemName: style.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(style.tint)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(rule.name.isEmpty ? localized("未命名指令") : rule.name)
                        .font(.duo(16, .heavy))
                        .foregroundStyle(Duo.eel)
                    if !rule.enabled {
                        DuoChip(text: "已停用", color: Duo.wolf, background: Duo.polar)
                    }
                }

                if !rule.phrases.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(rule.phrases.prefix(4), id: \.self) { phrase in
                            DuoChip(text: localized("「%@」", phrase), color: Duo.eel, background: Duo.polar)
                        }
                        if rule.phrases.count > 4 {
                            DuoChip(text: "+\(rule.phrases.count - 4)",
                                    color: Duo.wolf, background: Duo.polar)
                        }
                    }
                }

                Text(actionSummary(rule.action))
                    .font(.duo(11, .medium))
                    .foregroundStyle(Duo.wolf)
                    .lineLimit(2)
            }
            .opacity(rule.enabled ? 1 : 0.55)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { rule.enabled },
                    set: { model.setCommandEnabled(id: rule.id, enabled: $0) }
                ))
                .toggleStyle(DuoToggleStyle())
                .labelsHidden()
                .accessibilityLabel(rule.name.isEmpty ? localized("启用指令") : localized("启用 %@", rule.name))

                HStack(spacing: 4) {
                    if total > 1 {
                        MiniIconButton(systemName: "chevron.up") {
                            model.moveCommand(id: rule.id, offset: -1)
                        }
                        .disabled(index == 0)
                        .opacity(index == 0 ? 0.3 : 1)
                        MiniIconButton(systemName: "chevron.down") {
                            model.moveCommand(id: rule.id, offset: 1)
                        }
                        .disabled(index >= total - 1)
                        .opacity(index >= total - 1 ? 0.3 : 1)
                    }
                    MiniIconButton(systemName: "pencil") { edit() }
                        .accessibilityLabel("编辑")
                    MiniIconButton(systemName: "trash", tint: Duo.cardinal) {
                        model.deleteCommand(id: rule.id)
                    }
                    .accessibilityLabel("删除")
                }
            }
        }
        .duoCard(padding: 16)
    }
}

struct MiniIconButton: View {
    let systemName: String
    var tint: Color = Duo.wolf
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Duo.polar)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Duo.swan, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
