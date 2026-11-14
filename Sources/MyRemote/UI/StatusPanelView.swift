import SwiftUI
import AppKit

/// 菜单栏状态浮层：替代原生 NSMenu，和主界面使用同一套 Duolingo 配色。
struct StatusPanelView: View {

    @ObservedObject var model: SettingsModel
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    private struct StatusLanguage: Identifiable {
        let id: String
        let label: String
    }

    private let languages = [
        StatusLanguage(id: "auto", label: localized("自动")),
        StatusLanguage(id: "zh", label: localized("中文")),
        StatusLanguage(id: "en", label: "English"),
        StatusLanguage(id: "ja", label: "日本語"),
        StatusLanguage(id: "ko", label: "한국어"),
        StatusLanguage(id: "yue", label: localized("粤语")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            modeRow
            settingsCard
            statusCard
            actionGrid
            Spacer(minLength: 0)
            footer
        }
        .padding(12)
        .frame(width: 336, height: 560)
        .background(Duo.polar)
        .onAppear { model.refreshAudioStatus() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("MyRemote")
                    .font(.duo(15, .heavy))
                    .foregroundStyle(Duo.eel)
                HStack(spacing: 5) {
                    DuoDot(color: model.snapshot.atvvConnected ? Duo.owl : Duo.hare, size: 7)
                    Text(model.snapshot.atvvConnected ? localized("遥控器已连接") : localized("遥控器未连接"))
                        .font(.duo(10, .bold))
                        .foregroundStyle(Duo.wolf)
                    if let battery = model.snapshot.battery {
                        Text("· \(battery)%")
                            .font(.duo(10, .bold))
                            .foregroundStyle(Duo.hare)
                    }
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Duo.wolf)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Duo.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
    }

    private var modeRow: some View {
        HStack(spacing: 6) {
            ForEach(VoiceMode.allCases) { mode in
                ModeChip(mode: mode, selected: model.snapshot.voiceMode == mode) {
                    model.setVoiceMode(mode)
                }
            }
        }
    }

    // MARK: - 快捷设置

    private var settingsCard: some View {
        VStack(spacing: 0) {
            languageRow
            rowDivider
            toggleRow("自动粘贴到前台输入框", icon: "doc.on.clipboard",
                      isOn: Binding(get: { model.config.autoPaste },
                                    set: { model.setAutoPaste($0) }))
            rowDivider
            toggleRow("模式切换音效", icon: "speaker.wave.2.fill",
                      isOn: Binding(get: { model.config.modeSoundsEnabled },
                                    set: { model.setModeSounds($0) }))
            rowDivider
            toggleRow("音频输入模式共享音频", icon: "waveform.path.ecg",
                      isOn: Binding(get: { model.config.shareVoiceToBlackHole },
                                    set: { model.setShareVoice($0) }))
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Duo.white)
        )
    }

    private var languageRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "globe")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Duo.wolf)
                .frame(width: 16)
            Text("识别语言")
                .font(.duo(12, .bold))
                .foregroundStyle(Duo.eel)
            Spacer()
            Menu {
                ForEach(languages) { language in
                    Button {
                        model.setLanguage(language.id)
                    } label: {
                        Text(model.config.language == language.id
                             ? "✓ \(language.label)" : language.label)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(languageLabel)
                        .font(.duo(11, .heavy))
                        .foregroundStyle(Duo.eel)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Duo.hare)
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(Duo.polar))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Duo.wolf)
                .frame(width: 16)
            Text(title.localized)
                .font(.duo(12, .bold))
                .foregroundStyle(Duo.eel)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(DuoToggleStyle())
                .labelsHidden()
                .scaleEffect(0.82)
                .frame(width: 44)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Duo.swan.opacity(0.6))
            .frame(height: 1)
            .padding(.leading, 35)
    }

    // MARK: - 状态

    private var statusCard: some View {
        VStack(spacing: 0) {
            statusRow(icon: "cpu", title: "语音模型",
                      value: modelText,
                      color: model.snapshot.modelReady ? Duo.treeFrog
                        : (model.snapshot.modelDownloading ? Duo.whale : Duo.hare),
                      actionTitle: model.snapshot.modelReady || model.snapshot.modelDownloading
                        ? nil : "下载",
                      action: { model.downloadModel() })

            rowDivider
            statusRow(icon: "waveform", title: "虚拟声卡",
                      value: blackHoleText,
                      color: model.snapshot.blackHoleDeviceOnline ? Duo.treeFrog : Duo.hare,
                      actionTitle: model.snapshot.blackHoleInstalled ? nil : "了解",
                      action: {
                          NSWorkspace.shared.open(URL(string: "https://existential.audio/blackhole/")!)
                      })

            if let missing = Permissions.firstMissing {
                rowDivider
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Duo.beeDark)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("权限未完成")
                            .font(.duo(12, .bold))
                            .foregroundStyle(Duo.eel)
                        Text(missing == .accessibility ? localized("需要辅助功能") : localized("需要输入监控"))
                            .font(.duo(9, .medium))
                            .foregroundStyle(Duo.wolf)
                    }
                    Spacer()
                    Button("向导") {
                        onClose()
                        PermissionGuideController.shared.show(missing)
                    }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 26))
                }
                .padding(.horizontal, 10)
                .frame(height: 42)
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Duo.white)
        )
    }

    private func statusRow(icon: String, title: String, value: String, color: Color,
                           actionTitle: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Duo.wolf)
                .frame(width: 16)
            Text(title.localized)
                .font(.duo(12, .bold))
                .foregroundStyle(Duo.eel)
            Spacer()
            Text(value.localized)
                .font(.duo(10, .heavy))
                .foregroundStyle(color)
            if let actionTitle {
                Button(actionTitle.localized, action: action)
                    .buttonStyle(DuoSecondaryButtonStyle(height: 24))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    // MARK: - 操作

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)], spacing: 8) {
            actionButton("权限向导", icon: "hand.raised.fill") {
                onClose()
                if let kind = Permissions.firstMissing {
                    PermissionGuideController.shared.show(kind)
                } else {
                    Toast.shared.show("辅助功能与输入监控都已授权")
                }
            }
            actionButton("打开设置", icon: "gearshape.fill") {
                onClose()
                onOpenSettings()
            }
            actionButton("编辑指令", icon: "bolt.fill") {
                onClose()
                onOpenSettings()
            }
            actionButton("打开日志", icon: "doc.text.fill") {
                onClose()
                NSWorkspace.shared.open(Log.fileURL)
            }
            actionButton("重新连接", icon: "arrow.clockwise") {
                model.restartRemote()
            }
            if model.snapshot.lastTranscript != nil {
                actionButton("复制识别", icon: "doc.on.doc") {
                    model.services.copyLastTranscript()
                    onClose()
                }
            } else {
                actionButton("试听音效", icon: "speaker.wave.2") {
                    model.previewModeSound()
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String,
                              danger: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title.localized)
                    .font(.duo(11, .heavy))
            }
            .foregroundStyle(danger ? Duo.cardinal : Duo.eel)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(danger ? Duo.walkingFish : Duo.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(danger ? Duo.fireAnt.opacity(0.4) : Duo.swan, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(versionText)
                .font(.duo(9, .medium))
                .foregroundStyle(Duo.hare)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .black))
                    Text("退出 MyRemote")
                }
            }
            .buttonStyle(DuoPrimaryButtonStyle(color: Duo.cardinal,
                                               lip: Duo.fireAnt,
                                               height: 32,
                                               radius: 11))
            .accessibilityLabel("退出 MyRemote")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 文案

    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon.icns")
        if let image = NSImage(contentsOf: local) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.13.0"
        return "v\(version) · SenseVoice"
    }

    private var languageLabel: String {
        languages.first(where: { $0.id == model.config.language })?.label ?? "自动"
    }

    private var modelText: String {
        if model.snapshot.modelDownloading {
            return String(format: "下载 %.0f%%", model.snapshot.modelProgress * 100)
        }
        return model.snapshot.modelReady ? "已就绪" : "未下载"
    }

    private var blackHoleText: String {
        if !model.snapshot.blackHoleInstalled { return "未安装" }
        return model.snapshot.blackHoleDeviceOnline ? "在线" : "离线"
    }
}
