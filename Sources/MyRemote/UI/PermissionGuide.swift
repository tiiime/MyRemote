import Foundation
import AppKit
import SwiftUI
import ApplicationServices
import IOKit.hid
import CoreBluetooth

// MARK: - 权限类型

enum PermissionKind: String, CaseIterable {
    case accessibility
    case inputMonitoring

    var title: String {
        switch self {
        case .accessibility: return localized("开启辅助功能")
        case .inputMonitoring: return localized("开启输入监控")
        }
    }

    var subtitle: String {
        switch self {
        case .accessibility: return localized("接管按键、投递媒体键与粘贴")
        case .inputMonitoring: return localized("读取遥控器返回键")
        }
    }

    var paneURL: String {
        switch self {
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
    }

    var settingsName: String {
        switch self {
        case .accessibility: return localized("辅助功能")
        case .inputMonitoring: return localized("输入监控")
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: return Permissions.accessibility
        case .inputMonitoring: return Permissions.inputMonitoring
        }
    }

    var next: PermissionKind? {
        switch self {
        case .accessibility:
            return Permissions.inputMonitoring ? nil : .inputMonitoring
        case .inputMonitoring:
            return nil
        }
    }
}

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    static var inputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static var bluetooth: Bool {
        CBCentralManager.authorization == .allowedAlways
    }

    /// 第一个缺失的权限（用于菜单/设置里的「权限向导」）。
    static var firstMissing: PermissionKind? {
        if !accessibility { return .accessibility }
        if !inputMonitoring { return .inputMonitoring }
        return nil
    }
}

// MARK: - 悬浮窗位置

enum PermissionGuideSide {
    case left
    case right
    case above
}

enum PermissionGuidePlacement {

    /// 优先贴系统设置窗口右侧，其次左侧，放不下时覆盖底部；始终限制在屏幕可见范围内。
    static func frame(settings: CGRect?, visible: CGRect, size: CGSize) -> CGRect {
        let width = min(size.width, max(1, visible.width - 24))
        let height = min(size.height, max(1, visible.height - 24))
        guard let settings else {
            return CGRect(x: visible.maxX - width - 24,
                          y: visible.maxY - height - 80,
                          width: width, height: height)
        }

        var x = settings.maxX + 16
        if x + width > visible.maxX - 12 {
            x = settings.minX - width - 16
        }
        var y = min(max(settings.maxY - height - 36, visible.minY + 12),
                    visible.maxY - height - 12)

        if x < visible.minX + 12 {
            // 两侧都放不下：覆盖在设置窗口底部，像 DSH 的引导条。
            x = settings.midX - width / 2
            y = min(max(settings.minY + 8, visible.minY + 12),
                    visible.maxY - height - 12)
        }
        x = min(max(x, visible.minX + 12), visible.maxX - width - 12)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func side(settings: CGRect?, panel: CGRect) -> PermissionGuideSide {
        guard let settings else { return .left }
        if panel.midX >= settings.midX { return .left }
        return .right
    }
}

// MARK: - 悬浮窗内容模型

final class PermissionGuideModel: ObservableObject {
    let kind: PermissionKind
    let appURL: URL?
    let appIcon: NSImage
    let appName: String

    @Published var granted: Bool
    @Published var waitingAfterDrop = false
    @Published var arrow: PermissionGuideSide = .left

    init(kind: PermissionKind, appURL: URL?, appIcon: NSImage, appName: String, granted: Bool) {
        self.kind = kind
        self.appURL = appURL
        self.appIcon = appIcon
        self.appName = appName
        self.granted = granted
    }

    var canDrag: Bool { appURL != nil }

    var statusText: String {
        if granted { return localized("已授权") }
        if waitingAfterDrop { return localized("等待授权…") }
        return localized("待授权")
    }

    var statusColor: Color {
        granted ? Duo.treeFrog : (waitingAfterDrop ? Duo.whale : Duo.beeDark)
    }

    var statusBackground: Color {
        granted ? Duo.seaSponge : (waitingAfterDrop ? Duo.iguana : Duo.beeLight)
    }
}

// MARK: - 拖拽图标（AppKit）

struct AppIconDragSource: NSViewRepresentable {
    let url: URL?
    let icon: NSImage
    let onDragBegan: () -> Void
    let onDragEnded: (NSDragOperation) -> Void

    func makeNSView(context: Context) -> DragIconView {
        let view = DragIconView()
        view.url = url
        view.icon = icon
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: DragIconView, context: Context) {
        view.url = url
        view.icon = icon
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
        view.needsDisplay = true
    }
}

final class DragIconView: NSView, NSDraggingSource {

    var url: URL?
    var icon: NSImage = NSImage()
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((NSDragOperation) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url else {
            NSSound.beep()
            return
        }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: bounds.insetBy(dx: 2, dy: 2))
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragBegan?()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onDragEnded?(operation)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

// MARK: - 悬浮窗 View

struct PermissionGuideView: View {

    @ObservedObject var model: PermissionGuideModel
    var onOpenSettings: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void
    var onReveal: () -> Void
    var onDragBegan: () -> Void
    var onDragEnded: (NSDragOperation) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if model.arrow == .left {
                arrowBadge("arrow.left")
            }
            content
            if model.arrow == .right {
                arrowBadge("arrow.right")
            }
        }
        .padding(6)
        .frame(width: 492, height: 330)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dragRow
            updateTip
            footer
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Duo.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Duo.swan, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.appIcon)
                .resizable()
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.kind.title)
                    .font(.duo(17, .heavy))
                    .foregroundStyle(Duo.eel)
                Text(model.kind.subtitle)
                    .font(.duo(10, .medium))
                    .foregroundStyle(Duo.wolf)
            }
            Spacer()
            HStack(spacing: 5) {
                DuoDot(color: model.granted ? Duo.owl : Duo.beeDark, size: 7)
                Text(model.statusText)
                    .font(.duo(10, .heavy))
                    .foregroundStyle(model.statusColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(model.statusBackground))
        }
    }

    private var dragRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Duo.owl.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 58, height: 58)
                if model.canDrag {
                    AppIconDragSource(url: model.appURL, icon: model.appIcon,
                                      onDragBegan: onDragBegan, onDragEnded: onDragEnded)
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Duo.beeDark)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.canDrag
                     ? localized("把 %@ 拖进「%@」列表", model.appName, model.kind.settingsName)
                     : localized("请从 MyRemote.app 启动后再拖拽"))
                    .font(.duo(13, .heavy))
                    .foregroundStyle(Duo.eel)
                Text(model.canDrag
                     ? "拖不动：系统设置 → + → 选择 MyRemote；列表里已有 MyRemote 时直接打开开关即可"
                     : "命令行直接运行二进制时无法拖拽")
                    .font(.duo(10, .medium))
                    .foregroundStyle(Duo.wolf)
                    .fixedSize(horizontal: false, vertical: true)
                if model.waitingAfterDrop && !model.granted {
                    Text("已拖入，请在系统设置里勾选 MyRemote")
                        .font(.duo(10, .bold))
                        .foregroundStyle(Duo.whale)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Duo.polar)
        )
    }

    @ViewBuilder
    private var updateTip: some View {
        if !model.granted {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold))
                Text("更新过 App？先在列表里选中旧的 MyRemote，点「−」删除，再把新图标拖进来；旧勾选对新版本无效。")
                    .font(.duo(10, .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Duo.eel)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Duo.beeLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Duo.bee.opacity(0.5), lineWidth: 1.5)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.canDrag {
                Button("在 Finder 中显示") { onReveal() }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 34))
            }
            Spacer()
            Button("完成") { onClose() }
                .buttonStyle(DuoSecondaryButtonStyle(height: 34))
            Button(primaryTitle) {
                if model.granted && model.kind.next != nil {
                    onNext()
                } else if model.granted {
                    onClose()
                } else {
                    onOpenSettings()
                }
            }
            .buttonStyle(DuoPrimaryButtonStyle(height: 34))
        }
    }

    private var primaryTitle: String {
        if model.granted {
            if let next = model.kind.next {
                return localized("下一步：%@", next.settingsName)
            }
            return localized("完成")
        }
        return localized("打开系统设置")
    }

    private func arrowBadge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(Duo.owl)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Duo.seaSponge))
            .padding(.horizontal, 2)
    }
}

// MARK: - 控制器

final class PermissionGuideController {

    static let shared = PermissionGuideController()

    private var panel: NSPanel?
    private var model: PermissionGuideModel?
    private var kind: PermissionKind = .accessibility
    private var timer: Timer?
    private var settingsWindowID: CGWindowID?
    private var dragging = false
    private var settingsSeen = false

    private var appURL: URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app",
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private var appIcon: NSImage {
        if let url = appURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "playpause.circle.fill",
                       accessibilityDescription: nil) ?? NSImage()
    }

    private var appName: String {
        appURL?.lastPathComponent ?? "MyRemote.app"
    }

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: 展示

    func show(_ kind: PermissionKind) {
        self.kind = kind
        dragging = false
        settingsSeen = false
        settingsWindowID = nil
        if panel != nil { dismiss() }

        let model = PermissionGuideModel(kind: kind, appURL: appURL,
                                         appIcon: appIcon, appName: appName,
                                         granted: kind.isGranted)
        self.model = model
        buildPanel(model: model)

        openSettingsPane(kind)
        panel?.orderFrontRegardless()
        startTimer()
        updatePosition()
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        model = nil
        settingsWindowID = nil
        dragging = false
        settingsSeen = false
    }

    // MARK: 面板

    private func buildPanel(model: PermissionGuideModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 492, height: 330),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let view = PermissionGuideView(
            model: model,
            onOpenSettings: { [weak self] in
                guard let self else { return }
                self.openSettingsPane(self.kind)
                self.panel?.orderFrontRegardless()
                self.updatePosition()
            },
            onNext: { [weak self] in
                guard let self, let next = self.kind.next else { return }
                self.show(next)
            },
            onClose: { [weak self] in self?.dismiss() },
            onReveal: { [weak self] in
                guard let self, let url = self.appURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            onDragBegan: { [weak self] in
                guard let self else { return }
                self.dragging = true
                self.panel?.orderOut(nil)
            },
            onDragEnded: { [weak self] operation in
                guard let self else { return }
                self.dragging = false
                self.model?.waitingAfterDrop = true
                self.panel?.orderFrontRegardless()
                self.updatePosition()
                if operation.isEmpty {
                    self.model?.waitingAfterDrop = false
                }
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 492, height: 330)
        panel.contentView = hosting
        self.panel = panel
        updatePosition()
    }

    private func openSettingsPane(_ kind: PermissionKind) {
        guard let url = URL(string: kind.paneURL) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: 跟随系统设置

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let model, panel != nil else { return }

        let granted = kind.isGranted
        if granted != model.granted {
            model.granted = granted
            if granted {
                model.waitingAfterDrop = false
            }
        }

        // 全部完成：短暂停留后自动收起。
        if granted && kind.next == nil {
            dismiss()
            return
        }

        guard !dragging else { return }
        updatePosition()
    }

    private func updatePosition() {
        guard let panel else { return }
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let screen else { return }

        if let window = settingsWindow() {
            settingsSeen = true
            settingsWindowID = window.id
            let frame = PermissionGuidePlacement.frame(settings: window.frame,
                                                       visible: screen.visibleFrame,
                                                       size: panel.frame.size)
            if panel.frame != frame {
                panel.setFrame(frame, display: true)
            }
            model?.arrow = PermissionGuidePlacement.side(settings: window.frame, panel: frame)
            if panel.isVisible {
                panel.order(.above, relativeTo: Int(window.id))
            }
        } else if settingsSeen {
            // 用户关掉了系统设置：引导也一起收起。
            dismiss()
        }
    }

    private struct SettingsWindow {
        let id: CGWindowID
        let frame: CGRect
    }

    /// 读取系统设置窗口（只用 bounds/owner，不需要辅助功能权限）。
    private func settingsWindow() -> SettingsWindow? {
        guard let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.systempreferences").first,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var best: SettingsWindow?
        var bestArea: CGFloat = 0

        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 400, rect.height > 300
            else { continue }

            let area = rect.width * rect.height
            if area > bestArea {
                bestArea = area
                best = SettingsWindow(
                    id: number.uint32Value,
                    frame: CGRect(x: rect.minX,
                                  y: primaryHeight - rect.maxY,
                                  width: rect.width,
                                  height: rect.height)
                )
            }
        }
        return best
    }
}
