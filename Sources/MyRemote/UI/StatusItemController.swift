import Foundation
import AppKit
import SwiftUI

/// 菜单栏图标 + 状态浮层。
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let services: AppServices
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let openSettings: () -> Void

    private var model: SettingsModel?
    private let dotView = StatusDotView()
    private var lastCloseAt: Date?
    private var observer: NSObjectProtocol?

    init(services: AppServices, openSettings: @escaping () -> Void) {
        self.services = services
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureButton()

        let model = SettingsModel(services: services)
        self.model = model
        let root = StatusPanelView(
            model: model,
            onClose: { [weak self] in self?.closePopover() },
            onOpenSettings: openSettings
        )
        popover.contentViewController = NSHostingController(rootView: root)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 336, height: 560)

        observer = NotificationCenter.default.addObserver(
            forName: .myRemoteStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - 图标

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.bodyImage()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "MyRemote"

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.5
        dotView.layer?.borderWidth = 1
        dotView.layer?.borderColor = NSColor.white.withAlphaComponent(0.95).cgColor
        dotView.autoresizingMask = [.minXMargin, .maxYMargin]
        button.addSubview(dotView)
        button.target = self
        button.action = #selector(handleStatusClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// 左键打开主界面，右键展开快捷浮层。
    @objc private func handleStatusClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            togglePopover(sender)
            return
        }
        if popover.isShown { closePopover() }
        openSettings()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
            return
        }
        // 点击状态项关闭 transient 浮层时，系统可能先关闭再触发 action；避免立刻重开。
        if let lastCloseAt, Date().timeIntervalSince(lastCloseAt) < 0.25 { return }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    /// 仅供本地预览：直接展开状态浮层。
    func showPopoverForPreview() {
        togglePopover(nil)
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func refresh() {
        let snapshot = services.snapshot
        let mode = snapshot.voiceMode

        if statusItem.button?.image == nil {
            statusItem.button?.image = StatusIcon.bodyImage()
        }
        dotView.layer?.backgroundColor = StatusIcon.badgeColor(for: mode).cgColor
        layoutDot()

        statusItem.button?.toolTip = localized("MyRemote · %@ · 左键打开界面，右键快捷面板", mode.title)
        statusItem.button?.appearsDisabled = snapshot.transcribing
    }

    private func layoutDot() {
        guard let button = statusItem.button else { return }
        let size: CGFloat = 7
        // NSStatusBarButton 是 flipped 的：y 从顶部往下算，底部要取 maxY - size。
        let y: CGFloat = button.isFlipped ? button.bounds.maxY - size - 2.0 : 2.0
        dotView.frame = NSRect(x: button.bounds.maxX - size - 1.5,
                               y: y, width: size, height: size)
    }

    func popoverDidClose(_ notification: Notification) {
        lastCloseAt = Date()
        statusItem.button?.highlight(false)
    }
}

/// 菜单栏图标：白色模板主体（跟随菜单栏自动黑/白反色）+ 独立彩色模式角点。
enum StatusIcon {

    /// 主体：SVG 遥控器（模板图片，跟随菜单栏自动黑/白反色）。
    static func bodyImage() -> NSImage {
        if let image = NSImage(data: Data(remoteSVG.utf8)) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        return fallback()
    }

    private static let remoteSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
      <rect x="4.1" y="0.9" width="9.8" height="16.2" rx="3.2"
            fill="none" stroke="#000000" stroke-width="1.6"/>
      <circle cx="9" cy="4.2" r="1.2" fill="#000000"/>
      <circle cx="9" cy="9.1" r="2.5" fill="none"
              stroke="#000000" stroke-width="1.5"/>
      <circle cx="9" cy="9.1" r="0.85" fill="#000000"/>
      <circle cx="7.15" cy="13.8" r="0.9" fill="#000000"/>
      <circle cx="10.85" cy="13.8" r="0.9" fill="#000000"/>
    </svg>
    """

    /// 右下角模式点：黄=默认转发，绿=action/命令，蓝=文字输入。
    static func badgeColor(for mode: VoiceMode) -> NSColor {
        switch mode {
        case .forward:
            return NSColor(calibratedRed: 1.000, green: 0.784, blue: 0.000, alpha: 1) // #FFC800
        case .command:
            return NSColor(calibratedRed: 0.345, green: 0.800, blue: 0.008, alpha: 1) // #58CC02
        case .input:
            return NSColor(calibratedRed: 0.110, green: 0.690, blue: 0.965, alpha: 1) // #1CB0F6
        }
    }

    private static func fallback() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 5, y: 3.5))
            path.line(to: NSPoint(x: 15, y: 9))
            path.line(to: NSPoint(x: 5, y: 14.5))
            path.close()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// 只负责画彩色圆点，不参与点击命中。
final class StatusDotView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
