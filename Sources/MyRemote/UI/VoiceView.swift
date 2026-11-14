import SwiftUI
import AppKit

struct VoiceView: View {

    @ObservedObject var model: SettingsModel

    private let languages: [(code: String, label: String, hint: String)] = [
        ("auto", localized("自动"), localized("自动判断语种")),
        ("zh", localized("中文"), localized("普通话")),
        ("en", "English", localized("英语")),
        ("ja", "日本語", localized("日语")),
        ("ko", "한국어", localized("韩语")),
        ("yue", localized("粤语"), localized("粤语")),
    ]

    var body: some View {
        VStack(spacing: 16) {
            languageCard
            voiceShareCard
            HStack(alignment: .top, spacing: 16) {
                optionsCard
                modelCard
            }
            transcriptCard
        }
        .onAppear { model.refreshAudioStatus() }
    }

    // MARK: - 语音共享

    private var voiceShareCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            DuoCardHeader(title: "语音共享", icon: "waveform.path.ecg", tint: Duo.lily,
                          trailing: AnyView(DuoChip(
                            text: model.config.shareVoiceToBlackHole ? "已开启" : "已关闭",
                            color: model.config.shareVoiceToBlackHole ? Duo.treeFrog : Duo.wolf,
                            background: model.config.shareVoiceToBlackHole ? Duo.seaSponge : Duo.polar)))

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("共享到 BlackHole 2ch")
                        .font(.duo(14, .bold))
                        .foregroundStyle(Duo.eel)
                    Text("仅在音频输入模式下写入虚拟声卡；命令 / 文字输入模式不转发音频")
                        .font(.duo(11, .medium))
                        .foregroundStyle(Duo.wolf)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { model.config.shareVoiceToBlackHole },
                    set: { model.setShareVoice($0) }
                ))
                .toggleStyle(DuoToggleStyle())
                .labelsHidden()
                .accessibilityLabel("共享语音到 BlackHole 2ch")
            }

            HStack(spacing: 8) {
                shareStatusChip(title: "驱动", ok: model.snapshot.blackHoleInstalled,
                                okText: "已安装", badText: "未安装")
                shareStatusChip(title: "设备", ok: model.snapshot.blackHoleDeviceOnline,
                                okText: "在线", badText: "离线")
                Spacer()
                Button("刷新") { model.refreshAudioStatus() }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 30))
            }

            if !model.snapshot.blackHoleInstalled {
                Text("需要先安装 BlackHole 2ch，安装后重启音频服务（或重启电脑）再回来刷新。")
                    .font(.duo(11, .medium))
                    .foregroundStyle(Duo.wolf)
                Button("获取 BlackHole") {
                    NSWorkspace.shared.open(URL(string: "https://existential.audio/blackhole/")!)
                }
                .buttonStyle(DuoPrimaryButtonStyle(height: 32))
            } else if !model.snapshot.blackHoleDeviceOnline {
                Text("驱动已安装但设备不在线：在「音频 MIDI 设置」里启用 BlackHole 2ch，或重启音频服务。")
                    .font(.duo(11, .medium))
                    .foregroundStyle(Duo.wolf)
            } else {
                Text("音频输入模式下，在微信 / 会议 / 录音软件里把麦克风选为 BlackHole 2ch；命令 / 文字输入模式不会转发。系统默认麦克风不会被改动。")
                    .font(.duo(11, .medium))
                    .foregroundStyle(Duo.wolf)
            }
        }
        .duoCard()
    }

    private func shareStatusChip(title: String, ok: Bool,
                                 okText: String, badText: String) -> some View {
        DuoChip(text: "\(title)：\(ok ? okText : badText)",
                color: ok ? Duo.treeFrog : Duo.fireAnt,
                background: ok ? Duo.seaSponge : Duo.walkingFish,
                icon: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
    }

    // MARK: - 语言

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "识别语言", icon: "character.bubble.fill", tint: Duo.whale,
                          trailing: AnyView(DuoChip(text: "SenseVoice",
                                                    color: Duo.whale, background: Duo.iguana)))
            Text("中文、英文、日文、韩文、粤语；自动模式由模型判断。")
                .font(.duo(12, .medium))
                .foregroundStyle(Duo.wolf)

            FlowLayout(spacing: 8) {
                ForEach(languages, id: \.code) { language in
                    LanguageChip(
                        title: language.label,
                        hint: language.hint,
                        selected: model.config.language == language.code
                    ) {
                        model.setLanguage(language.code)
                    }
                }
            }
        }
        .duoCard()
    }

    // MARK: - 投递选项

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            DuoCardHeader(title: "投递方式", icon: "paperplane.fill", tint: Duo.owl)

            toggleRow(title: "文字输入模式下自动粘贴",
                      subtitle: "关闭后只把识别结果复制到剪贴板",
                      isOn: Binding(get: { model.config.autoPaste },
                                    set: { model.setAutoPaste($0) }))
            Divider().overlay(Duo.swan)
            toggleRow(title: "显示识别结果提示",
                      subtitle: "在屏幕底部弹出轻量结果气泡",
                      isOn: Binding(get: { model.config.showToast },
                                    set: { model.setToast($0) }))

            if model.config.autoPaste {
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("粘贴需要「辅助功能」权限")
                        .font(.duo(11, .medium))
                }
                .foregroundStyle(Duo.wolf)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard()
    }

    private func toggleRow(title: String, subtitle: String,
                           isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.localized)
                    .font(.duo(14, .bold))
                    .foregroundStyle(Duo.eel)
                Text(subtitle.localized)
                    .font(.duo(11, .medium))
                    .foregroundStyle(Duo.wolf)
            }
            Spacer(minLength: 10)
            Toggle("", isOn: isOn)
                .toggleStyle(DuoToggleStyle())
                .labelsHidden()
        }
    }

    // MARK: - 模型

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "语音模型", icon: "waveform", tint: Duo.lily,
                          trailing: AnyView(DuoChip(
                            text: model.snapshot.modelReady ? "已就绪"
                                : model.snapshot.modelDownloading ? "下载中" : "未下载",
                            color: model.snapshot.modelReady ? Duo.treeFrog
                                : model.snapshot.modelDownloading ? Duo.eel : Duo.wolf,
                            background: model.snapshot.modelReady ? Duo.seaSponge
                                : model.snapshot.modelDownloading ? Duo.beeLight : Duo.polar)))

            if model.snapshot.modelDownloading {
                DuoProgressBar(value: model.snapshot.modelProgress, color: Duo.owl, height: 16)
                Text(model.snapshot.modelMessage.isEmpty
                     ? localized("正在下载 %lld%%", Int(model.snapshot.modelProgress * 100))
                     : model.snapshot.modelMessage)
                    .font(.duo(11, .medium))
                    .foregroundStyle(Duo.wolf)
            } else if model.snapshot.modelReady {
                Text("SenseVoiceSmall int8 已加载，音频不出本机。")
                    .font(.duo(12, .medium))
                    .foregroundStyle(Duo.wolf)
            } else {
                Text("首次使用需要下载约 239MB 模型，下载后完全离线识别。")
                    .font(.duo(12, .medium))
                    .foregroundStyle(Duo.wolf)
                    .fixedSize(horizontal: false, vertical: true)
                Button("下载语音模型") { model.downloadModel() }
                    .buttonStyle(DuoPrimaryButtonStyle(expand: true))
            }

            Text(model.services.modelDirectory.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Duo.hare)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard()
    }

    // MARK: - 最近识别

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DuoCardHeader(title: "最近识别", icon: "text.bubble.fill", tint: Duo.macaw)
            if let transcript = model.snapshot.lastTranscript, !transcript.isEmpty {
                Text(transcript)
                    .font(.duo(15, .medium))
                    .foregroundStyle(Duo.eel)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Duo.iguana)
                    )
                Button("复制到剪贴板") { model.services.copyLastTranscript() }
                    .buttonStyle(DuoSecondaryButtonStyle())
            } else {
                Text("还没有识别记录。按遥控器语音键说一句话试试。")
                    .font(.duo(12, .medium))
                    .foregroundStyle(Duo.wolf)
            }
        }
        .duoCard()
    }
}

// MARK: - 语言胶囊

struct LanguageChip: View {
    let title: String
    let hint: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.localized)
                    .font(.duo(13, .heavy))
                Text(hint.localized)
                    .font(.duo(9, .medium))
                    .opacity(0.75)
            }
            .foregroundStyle(selected ? Duo.white : Duo.eel)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? Duo.owl : Duo.polar)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Duo.treeFrog : Duo.swan, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
