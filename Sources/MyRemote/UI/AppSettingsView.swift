import SwiftUI
import AppKit
import CoreBluetooth
import IOKit.hid

struct AppSettingsView: View {

    @ObservedObject var model: SettingsModel

    @State private var language = AppLanguage.current
    @State private var accessibilityOK = Permissions.accessibility
    @State private var inputMonitoringOK = Permissions.inputMonitoring
    @State private var bluetoothOK = Permissions.bluetooth

    var body: some View {
        VStack(spacing: 16) {
            remoteCard
            permissionsCard
            languageCard
            environmentCard
        }
        .onAppear(perform: refreshPermissions)
    }

    // MARK: - 遥控器

    private var remoteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            DuoCardHeader(title: "遥控器与工作模式", icon: "dot.radiowaves.left.and.right", tint: Duo.owl,
                          trailing: AnyView(DuoChip(
                            text: model.snapshot.atvvConnected ? "已连接" : "未连接",
                            color: model.snapshot.atvvConnected ? Duo.treeFrog : Duo.fireAnt,
                            background: model.snapshot.atvvConnected ? Duo.seaSponge : Duo.walkingFish)))

            VStack(alignment: .leading, spacing: 10) {
                Text("模式切换键")
                    .font(.duo(13, .bold))
                    .foregroundStyle(Duo.eel)
                HStack(spacing: 8) {
                    ModeKeyBadge(key: "Home", mode: .forward)
                    ModeKeyBadge(key: "TV", mode: .command)
                    ModeKeyBadge(key: "Menu", mode: .input)
                }
                HStack(spacing: 10) {
                    Text("模式切换音效")
                        .font(.duo(12, .bold))
                        .foregroundStyle(Duo.eel)
                    Toggle("", isOn: Binding(
                        get: { model.config.modeSoundsEnabled },
                        set: { model.setModeSounds($0) }
                    ))
                    .toggleStyle(DuoToggleStyle())
                    .labelsHidden()
                    Button("试听") { model.previewModeSound() }
                        .buttonStyle(DuoSecondaryButtonStyle(height: 30))
                }
            }

            HStack(spacing: 8) {
                ForEach(VoiceMode.allCases) { mode in
                    ModeChip(mode: mode, selected: model.snapshot.voiceMode == mode) {
                        model.setVoiceMode(mode)
                    }
                }
                Spacer()
                Button("重新连接遥控器") { model.restartRemote() }
                    .buttonStyle(DuoSecondaryButtonStyle())
            }
        }
        .duoCard()
    }

    // MARK: - 权限

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "系统权限", icon: "checkmark.shield.fill", tint: Duo.macaw)
            permissionRow(icon: "accessibility",
                          title: "辅助功能",
                          detail: "接管按键、投递媒体键与粘贴",
                          granted: accessibilityOK) {
                PermissionGuideController.shared.show(.accessibility)
            }
            Divider().overlay(Duo.swan)
            permissionRow(icon: "keyboard",
                          title: "输入监控",
                          detail: "读取遥控器返回键",
                          granted: inputMonitoringOK) {
                PermissionGuideController.shared.show(.inputMonitoring)
            }
            Divider().overlay(Duo.swan)
            permissionRow(icon: "dot.radiowaves.left.and.right",
                          title: "蓝牙",
                          detail: "连接遥控器语音通道",
                          granted: bluetoothOK) {
                TextInjector.openBluetoothSettings()
            }

            HStack(spacing: 10) {
                Button("刷新权限状态") { refreshPermissions() }
                    .buttonStyle(DuoSecondaryButtonStyle())
                Button("打开权限向导") {
                    if let kind = Permissions.firstMissing {
                        PermissionGuideController.shared.show(kind)
                    } else {
                        Toast.shared.show("辅助功能与输入监控都已授权")
                    }
                }
                .buttonStyle(DuoSecondaryButtonStyle())
            }
            Text("从旧版本更新后，如果列表里出现重复或失效的 MyRemote，请先选中旧条目点「−」删除，再重新拖入。")
                .font(.duo(10, .medium))
                .foregroundStyle(Duo.hare)
        }
        .duoCard()
    }

    private func permissionRow(icon: String, title: String, detail: String,
                               granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(granted ? Duo.seaSponge : Duo.beeLight)
                    .frame(width: 36, height: 36)
                Image(systemName: granted ? "checkmark" : "exclamationmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(granted ? Duo.treeFrog : Duo.beeDark)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title.localized)
                    .font(.duo(13, .bold))
                    .foregroundStyle(Duo.eel)
                Text(detail.localized)
                    .font(.duo(10, .medium))
                    .foregroundStyle(Duo.wolf)
            }
            Spacer()
            Text(granted ? localized("已授权") : localized("未授权"))
                .font(.duo(11, .heavy))
                .foregroundStyle(granted ? Duo.treeFrog : Duo.fireAnt)
            if !granted {
                Button("去授权", action: action)
                    .buttonStyle(DuoSecondaryButtonStyle(height: 32))
            }
        }
    }

    // MARK: - 语言

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "界面语言", icon: "globe", tint: Duo.macaw,
                          trailing: AnyView(DuoChip(text: AppLanguage.effective.title,
                                                    color: Duo.whale, background: Duo.iguana)))

            HStack(spacing: 8) {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        guard option != language else { return }
                        language = option
                        AppLanguage.apply(option)
                    } label: {
                        Text(option.title)
                            .font(.duo(12, .heavy))
                            .foregroundStyle(option == language ? Duo.whale : Duo.wolf)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(option == language ? Duo.iguana : Duo.polar)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(option == language ? Duo.macaw.opacity(0.55) : Duo.swan,
                                                  lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Text("切换后需要重启 MyRemote 才生效；「跟随系统」读取 macOS 的语言设置。")
                    .font(.duo(10, .medium))
                    .foregroundStyle(Duo.hare)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("立即重启") { AppRelauncher.relaunch() }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 30))
            }
        }
        .duoCard()
    }

    // MARK: - 环境

    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DuoCardHeader(title: "运行环境", icon: "wrench.and.screwdriver.fill", tint: Duo.fox)

            HStack(spacing: 12) {
                Image(systemName: model.legacyMiRemoteRunning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(model.legacyMiRemoteRunning ? Duo.beeDark : Duo.treeFrog)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.legacyMiRemoteRunning
                         ? localized("旧版 MiRemote 正在运行")
                         : localized("没有检测到旧版 MiRemote"))
                        .font(.duo(13, .bold))
                        .foregroundStyle(Duo.eel)
                    Text(model.legacyMiRemoteRunning
                         ? localized("两者会争抢遥控器，请退出其中一个")
                         : localized("遥控器由本应用独占"))
                        .font(.duo(10, .medium))
                        .foregroundStyle(Duo.wolf)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Image(systemName: "hand.raised.slash.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(model.config.logTranscripts ? Duo.beeDark : Duo.treeFrog)
                VStack(alignment: .leading, spacing: 2) {
                    Text("把识别文本写入日志")
                        .font(.duo(13, .bold))
                        .foregroundStyle(Duo.eel)
                    Text(model.config.logTranscripts
                         ? "正文会以明文写进 ~/Library/Logs/MyRemote.log，仅用于排查问题"
                         : "默认只记录时长、语言和字数，不写正文")
                        .font(.duo(10, .medium))
                        .foregroundStyle(Duo.wolf)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.config.logTranscripts },
                    set: { model.setLogTranscripts($0) }
                ))
                .toggleStyle(DuoToggleStyle())
                .labelsHidden()
            }

            HStack(spacing: 10) {
                Button("打开日志") { NSWorkspace.shared.open(Log.fileURL) }
                    .buttonStyle(DuoSecondaryButtonStyle())
                Text(Log.fileURL.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Duo.hare)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Text("MyRemote 0.12.8 · SenseVoice · sherpa-onnx · 语音链路移植自 MiRemote（MIT）")
                .font(.duo(10, .medium))
                .foregroundStyle(Duo.hare)
        }
        .duoCard()
    }

    private func refreshPermissions() {
        accessibilityOK = Permissions.accessibility
        inputMonitoringOK = Permissions.inputMonitoring
        bluetoothOK = Permissions.bluetooth
        model.refreshPermissions()
    }
}

struct ModeKeyBadge: View {
    let key: String
    let mode: VoiceMode

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.duo(10, .heavy))
                .foregroundStyle(Duo.eel)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Duo.white))
                .overlay(Capsule().strokeBorder(Duo.swan, lineWidth: 1.5))
            Text(mode.shortTitle)
                .font(.duo(11, .bold))
                .foregroundStyle(Duo.wolf)
        }
    }
}
