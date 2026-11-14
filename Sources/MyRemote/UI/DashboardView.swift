import SwiftUI

struct DashboardView: View {

    @ObservedObject var model: SettingsModel
    var navigate: (AppTab) -> Void

    var body: some View {
        VStack(spacing: 14) {
            hero
            // 同一行的两张卡片用自定义 Layout 拉成等高：
            // HStack 会让它们各自按内容撑高，底边就参差了。
            EqualHeightRowLayout(spacing: 18) {
                mediaCard
                modeCard
            }
            EqualHeightRowLayout(spacing: 18) {
                voiceCard
                dshCard
            }
            tipBar
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 13) {
                DuoSectionLabel(text: "当前遥控器")
                HStack(spacing: 10) {
                    Text(deviceTitle)
                        .font(.duo(30, .heavy))
                        .foregroundStyle(Duo.eel)
                        .lineLimit(1)
                    DuoChip(text: model.snapshot.atvvConnected ? "已连接" : "未连接",
                            color: model.snapshot.atvvConnected ? Duo.treeFrog : Duo.fireAnt,
                            background: model.snapshot.atvvConnected ? Duo.seaSponge : Duo.walkingFish)
                }
                Text(deviceHint)
                    .font(.duoBody)
                    .foregroundStyle(Duo.wolf)

                if let battery = model.snapshot.battery {
                    HStack(spacing: 10) {
                        Image(systemName: "battery.75percent")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Duo.wolf)
                        DuoProgressBar(value: Double(battery) / 100, height: 12)
                            .frame(width: 150)
                        Text("\(battery)%")
                            .font(.duo(12, .heavy))
                            .foregroundStyle(Duo.eel)
                    }
                }

                FlowLayout(spacing: 7) {
                    DuoChip(text: model.snapshot.mappingOK ? "按键接管正常" : "按键未接管",
                            color: model.snapshot.mappingOK ? Duo.treeFrog : Duo.fireAnt,
                            background: model.snapshot.mappingOK ? Duo.seaSponge : Duo.walkingFish,
                            icon: model.snapshot.mappingOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    DuoChip(text: model.snapshot.modelReady ? "语音就绪" : "模型未就绪",
                            color: model.snapshot.modelReady ? Duo.whale : Duo.wolf,
                            background: model.snapshot.modelReady ? Duo.iguana : Duo.polar,
                            icon: "waveform")
                    DuoChip(text: localized("%lld 条指令", model.config.commandRules.count),
                            color: Duo.lily, background: Duo.beetleLight,
                            icon: "bolt.fill")
                    DuoChip(text: model.snapshot.voiceMode.shortTitle,
                            color: model.snapshot.voiceMode.tintColor,
                            background: model.snapshot.voiceMode.backgroundColor,
                            icon: model.snapshot.voiceMode.icon)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 14) {
                DashboardStat(value: "\(model.config.commandRules.filter(\.enabled).count)",
                              label: "启用指令", tint: Duo.owl)
                DashboardStat(value: AppServices.languageLabel(model.config.language),
                              label: "识别语言", tint: Duo.macaw)
                DashboardStat(value: dshTitle, label: "DSH 目标", tint: Duo.lily)
            }
            .frame(width: 120)
        }
        .duoCard(padding: 20)
    }

    private var deviceTitle: String {
        if model.snapshot.atvvConnected {
            return model.snapshot.deviceName.isEmpty ? localized("小米遥控器") : model.snapshot.deviceName
        }
        return localized("等待遥控器")
    }

    private var deviceHint: String {
        if model.snapshot.atvvConnected {
            return localized("蓝牙语音通道与 HID 按键均已就绪")
        }
        return localized("打开遥控器电源，或在系统蓝牙里重新连接")
    }

    private var dshTitle: String {
        guard let rule = model.config.commandRules.first(where: { $0.isSendToDSH }),
              case .sendToDSH(_, let title, _) = rule.action else { return localized("未配置") }
        return title.isEmpty ? localized("未命名") : title
    }

    // MARK: - 播放控制

    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            DuoCardHeader(title: "播放控制", icon: "play.circle.fill", tint: Duo.macaw,
                          trailing: AnyView(DuoChip(text: "系统媒体键",
                                                    color: Duo.whale, background: Duo.iguana)))
            HStack(spacing: 14) {
                DuoIconButton(systemName: "backward.fill", tint: Duo.whale,
                              background: Duo.iguana, size: 44) {
                    MediaController.post(.previous)
                }

                Button {
                    MediaController.post(.playPause)
                } label: {
                    ZStack(alignment: .bottom) {
                        Circle().fill(Duo.treeFrog).frame(width: 64, height: 64).offset(y: 4)
                        Circle()
                            .fill(Duo.owl)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 24, weight: .black))
                                    .foregroundStyle(.white)
                                    .offset(x: 2)
                            )
                    }
                    .frame(width: 64, height: 68)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放或暂停")

                DuoIconButton(systemName: "forward.fill", tint: Duo.whale,
                              background: Duo.iguana, size: 44) {
                    MediaController.post(.next)
                }

                Spacer(minLength: 4)

                VStack(spacing: 8) {
                    DuoIconButton(systemName: "speaker.plus.fill", tint: Duo.whale,
                                  background: Duo.iguana, size: 32) {
                        MediaController.post(.volumeUp)
                    }
                    DuoIconButton(systemName: "speaker.minus.fill", tint: Duo.whale,
                                  background: Duo.iguana, size: 32) {
                        MediaController.post(.volumeDown)
                    }
                }
            }
            Spacer(minLength: 0)

            Text("OK 播放 / 暂停 · ← → 切歌 · ↑ ↓ 音量")
                .font(.duo(11, .medium))
                .foregroundStyle(Duo.wolf)
        }
        .duoCard()
    }

    // MARK: - 工作模式

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "工作模式", icon: model.snapshot.voiceMode.icon,
                          tint: Duo.eel,
                          trailing: AnyView(DuoChip(text: "Home · TV · Menu",
                                                    color: Duo.wolf, background: Duo.polar)))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.snapshot.voiceMode.title)
                    .font(.duo(24, .heavy))
                    .foregroundStyle(Duo.eel)
                DuoDot(color: model.snapshot.voiceMode.tintColor, size: 9)
            }
            Text(model.snapshot.voiceMode.subtitle)
                .font(.duo(12, .medium))
                .foregroundStyle(Duo.wolf)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(VoiceMode.allCases) { mode in
                    ModeChip(mode: mode,
                             selected: model.snapshot.voiceMode == mode) {
                        model.setVoiceMode(mode)
                    }
                }
            }

            Text("Home 音频输入 · TV 命令 · Menu 文字输入")
                .font(.duo(10, .medium))
                .foregroundStyle(Duo.hare)

            if model.snapshot.voiceMode == .command,
               let last = model.snapshot.lastCommand, !last.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .bold))
                    Text(localized("最近执行：%@", last))
                        .font(.duo(11, .bold))
                }
                .foregroundStyle(Duo.wolf)
            }

            Spacer(minLength: 0)
        }
        .duoCard()
    }

    // MARK: - 语音

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "语音输入", icon: "mic.fill", tint: Duo.whale,
                          trailing: AnyView(DuoChip(text: AppServices.languageLabel(model.config.language),
                                                    color: Duo.whale, background: Duo.white)))
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Duo.iguana).frame(width: 52, height: 52)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Duo.whale)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("按住语音键说话")
                        .font(.duo(15, .heavy))
                        .foregroundStyle(Duo.eel)
                    Text(listeningSubtitle)
                        .font(.duo(12, .medium))
                        .foregroundStyle(Duo.wolf)
                        .lineLimit(2)
                }
                Spacer()
            }
            if let transcript = model.snapshot.lastTranscript, !transcript.isEmpty {
                Text(transcript)
                    .font(.duo(12, .medium))
                    .foregroundStyle(Duo.eel)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Duo.white.opacity(0.75)))
            }
            Spacer(minLength: 0)
            Button("语音设置") { navigate(.voice) }
                .buttonStyle(DuoSecondaryButtonStyle())
        }
        .duoCard(Duo.iguana, border: Duo.macaw.opacity(0.4))
    }

    private var listeningSubtitle: String {
        if model.snapshot.capturing {
            if let partial = model.snapshot.partialTranscript, !partial.isEmpty {
                return "聆听中… \(partial)"
            }
            return "聆听中…"
        }
        if model.snapshot.transcribing {
            return localized("识别中…")
        }
        switch model.snapshot.voiceMode {
        case .forward: return localized("音频输入模式：只转发到 BlackHole")
        case .command: return localized("命令模式：识别为指令")
        case .input: return localized("文字输入模式：识别为文字")
        }
    }

    // MARK: - DSH

    private var dshCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "DSH 指令", icon: "sparkles", tint: Duo.lily,
                          trailing: AnyView(DuoChip(text: "DeepSeek Harness",
                                                    color: Duo.lily, background: Duo.white)))

            if let rule = model.config.commandRules.first(where: { $0.isSendToDSH }),
               case .sendToDSH(let sessionId, let title, let message) = rule.action {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title.isEmpty ? localized("未命名会话") : title)
                        .font(.duo(24, .heavy))
                        .foregroundStyle(Duo.eel)
                    DuoChip(text: sessionId.isEmpty ? "按标题解析" : "已绑定会话",
                            color: Duo.lily, background: Duo.white)
                }
                if !rule.phrases.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(rule.phrases.prefix(4), id: \.self) { phrase in
                            DuoChip(text: localized("「%@」", phrase), color: Duo.eel, background: Duo.white)
                        }
                    }
                }
                Text(message.isEmpty ? localized("发送识别文本") : localized("消息模板：%@", message))
                    .font(.duo(11, .medium))
                    .foregroundStyle(Duo.wolf)
            } else {
                Text("还没有发送到 DSH 会话的指令")
                    .font(.duo(13, .medium))
                    .foregroundStyle(Duo.wolf)
            }

            Spacer(minLength: 0)
            Button("编辑指令规则") { navigate(.commands) }
                .buttonStyle(DuoSecondaryButtonStyle())
        }
        .duoCard(Duo.beetleLight, border: Duo.beetle.opacity(0.45))
    }

    // MARK: - 提示条

    private var tipBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Duo.beeDark)
            Text("Home 音频输入 · TV 命令 · Menu 文字输入 · 语音键按住说话")
                .font(.duo(12, .medium))
                .foregroundStyle(Duo.wolf)
            Spacer()
            Button("打开设置") { navigate(.settings) }
                .buttonStyle(DuoSecondaryButtonStyle(height: 32))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Duo.beeLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Duo.bee.opacity(0.4), lineWidth: 1.5)
        )
    }
}

// MARK: - 小部件

private struct DashboardStat: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.duo(22, .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.localized)
                .font(.duo(10, .bold))
                .foregroundStyle(Duo.hare)
        }
    }
}

struct ModeChip: View {
    let mode: VoiceMode
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10, weight: .bold))
                Text(mode.shortTitle)
                    .font(.duo(11, .heavy))
            }
            .foregroundStyle(selected ? tint : Duo.wolf)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? background : Duo.polar)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.55) : Duo.swan, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var tint: Color { mode.tintColor }

    private var background: Color { mode.backgroundColor }
}

/// 一行两列、两列等高的容器。
///
/// HStack 只按内容给每列宽度、按内容给行高，所以同一行里内容少的卡片会矮一截，
/// 底边和卡片里的按钮就对不齐。这里先量出两列各自需要的高度，取大者，
/// 再用这个高度同时摆放两张卡片。
struct EqualHeightRowLayout: Layout {

    var spacing: CGFloat = 18

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let columnWidth = columnWidth(for: width)
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            height = max(height, size.height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = columnWidth(for: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let origin = CGPoint(x: bounds.minX + CGFloat(index) * (columnWidth + spacing),
                                 y: bounds.minY)
            subview.place(at: origin,
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: columnWidth, height: bounds.height))
        }
    }

    private func columnWidth(for width: CGFloat) -> CGFloat {
        max(0, (width - spacing) / 2)
    }
}
