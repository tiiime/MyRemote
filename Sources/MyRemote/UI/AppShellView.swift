import SwiftUI
import AppKit

// MARK: - 导航

/// 侧栏分组。标识不参与本地化，标题才跟语言走。
enum AppSection: String {
    case remote
    case settings

    var title: String {
        switch self {
        case .remote: return localized("遥控器")
        case .settings: return localized("配置")
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard
    case keymap
    case commands
    case voice
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return localized("概览")
        case .keymap: return localized("按键映射")
        case .commands: return localized("指令")
        case .voice: return localized("语音")
        case .settings: return localized("设置")
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return localized("遥控器、播放控制与语音状态一览")
        case .keymap: return localized("遥控器布局、分层与穿透")
        case .commands: return localized("语音指令的触发词与执行动作")
        case .voice: return localized("识别语言、模型与投递方式")
        case .settings: return localized("模式、权限与运行环境")
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .keymap: return "keyboard.fill"
        case .commands: return "bolt.fill"
        case .voice: return "mic.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var section: AppSection {
        switch self {
        case .dashboard, .keymap: return .remote
        default: return .settings
        }
    }
}

// MARK: - 外壳

struct AppShellView: View {

    @ObservedObject var model: SettingsModel
    @State private var tab: AppTab

    init(model: SettingsModel, tab: AppTab = .dashboard) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model, tab: $tab)
            VStack(spacing: 0) {
                header
                Divider().overlay(Duo.swan)
                ScrollView {
                    content
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.never)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Duo.polar)
        .preferredColorScheme(.light)
        .frame(minWidth: 960, minHeight: 700)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.title)
                    .font(.duo(28, .heavy))
                    .foregroundStyle(Duo.eel)
                Text(tab.subtitle)
                    .font(.duoCaption)
                    .foregroundStyle(Duo.wolf)
            }
            Spacer()
            statusChips
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .background(Duo.polar)
    }

    private var statusChips: some View {
        HStack(spacing: 8) {
            DuoChip(text: model.snapshot.atvvConnected ? "遥控器已连接" : "遥控器未连接",
                    color: model.snapshot.atvvConnected ? Duo.treeFrog : Duo.fireAnt,
                    background: model.snapshot.atvvConnected ? Duo.seaSponge : Duo.walkingFish,
                    icon: "dot.radiowaves.left.and.right")
            DuoChip(text: model.snapshot.modelReady ? "语音模型就绪" : "模型未就绪",
                    color: model.snapshot.modelReady ? Duo.whale : Duo.wolf,
                    background: model.snapshot.modelReady ? Duo.iguana : Duo.polar,
                    icon: "waveform")
            if model.snapshot.voiceMode != .forward {
                DuoChip(text: model.snapshot.voiceMode.title,
                        color: model.snapshot.voiceMode.tintColor,
                        background: model.snapshot.voiceMode.backgroundColor,
                        icon: model.snapshot.voiceMode.icon)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .dashboard:
            DashboardView(model: model, navigate: { tab = $0 })
        case .keymap:
            KeymapView(model: model)
        case .commands:
            CommandsView(model: model)
        case .voice:
            VoiceView(model: model)
        case .settings:
            AppSettingsView(model: model)
        }
    }
}

// MARK: - 侧边栏

struct SidebarView: View {

    @ObservedObject var model: SettingsModel
    @Binding var tab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            nav
            Spacer(minLength: 20)
            footer
        }
        .frame(width: 226)
        .background(Duo.white)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Duo.swan).frame(width: 2)
        }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            LogoMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("MyRemote")
                    .font(.duo(20, .heavy))
                    .foregroundStyle(Duo.eel)
                Text("遥控器控制台")
                    .font(.duo(10, .bold))
                    .foregroundStyle(Duo.hare)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 26)
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 4) {
            DuoSectionLabel(text: AppSection.remote.title)
                .padding(.horizontal, 22)
                .padding(.bottom, 6)

            ForEach(AppTab.allCases.filter { $0.section == .remote }) { item in
                SidebarItem(tab: item, selected: tab == item) { tab = item }
            }

            DuoSectionLabel(text: AppSection.settings.title)
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 6)

            ForEach(AppTab.allCases.filter { $0.section == .settings }) { item in
                SidebarItem(tab: item, selected: tab == item) { tab = item }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                DuoDot(color: model.snapshot.atvvConnected ? Duo.owl : Duo.cardinal, size: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.snapshot.atvvConnected ? localized("遥控器已连接") : localized("遥控器未连接"))
                        .font(.duo(12, .bold))
                        .foregroundStyle(Duo.eel)
                    Text(model.snapshot.battery.map { localized("电量 %@%%", "\($0)") } ?? localized("等待设备"))
                        .font(.duo(10, .medium))
                        .foregroundStyle(Duo.hare)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Duo.polar)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Duo.swan, lineWidth: 1.5)
            )

            Text("v0.12.8 · SenseVoice")
                .font(.duo(10, .medium))
                .foregroundStyle(Duo.hare)
                .padding(.horizontal, 2)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

struct SidebarItem: View {
    let tab: AppTab
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 20)
                Text(tab.title)
                    .font(.duo(14, .bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Duo.treeFrog : Duo.wolf)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? Duo.seaSponge : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Duo.treeFrog.opacity(0.35) : .clear,
                                  lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LogoMark: View {
    var size: CGFloat = 50

    private static let appIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon.icns")
        return NSImage(contentsOf: local)
    }()

    var body: some View {
        Group {
            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(Duo.treeFrog)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: size * 0.36, weight: .black))
                            .foregroundStyle(.white)
                    )
            }
        }
        .accessibilityLabel("MyRemote")
    }
}

// MARK: - 通用页面组件

/// 小标题 + 右侧操作。
struct DuoCardHeader: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Duo.eel
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(title.localized)
                .font(.duo(16, .heavy))
                .foregroundStyle(Duo.eel)
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// 空状态。
struct DuoEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Duo.seaSponge).frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Duo.treeFrog)
            }
            Text(title.localized)
                .font(.duo(17, .heavy))
                .foregroundStyle(Duo.eel)
            Text(message.localized)
                .font(.duoCaption)
                .foregroundStyle(Duo.wolf)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle.localized, action: action)
                    .buttonStyle(DuoPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .duoCard(padding: 30)
    }
}
