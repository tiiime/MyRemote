import Foundation
import AppKit

/// 屏幕底部的轻量提示（非激活浮层，不抢焦点）。
/// Duolingo 风格：白底、2px 描边、彩色图标、圆角。
final class Toast {

    static let shared = Toast()

    private var panel: NSPanel?
    private var container: NSView?
    private var iconCircle: NSView?
    private var iconView: NSImageView?
    private var label: NSTextField?
    private var hideWork: DispatchWorkItem?
    private let maxWidth: CGFloat = 520

    func show(_ text: String, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMain(text, duration: duration)
        }
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    // MARK: - 展示

    private func showOnMain(_ rawText: String, duration: TimeInterval) {
        let panel = ensurePanel()
        guard let container, let label, let iconView, let iconCircle else { return }

        let decoded = Self.decode(rawText)
        // 提示文案统一在这里过一遍本地化表；带数据的文案在调用处用 localized(_:_:) 拼好。
        let text = decoded.text.localized
        let font = Self.roundedFont(size: 13, weight: .bold)
        label.font = font
        label.stringValue = text

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth - 86, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let textWidth = min(maxWidth - 86, ceil(bounds.width))
        let width = max(180, min(maxWidth, textWidth + 86))
        let height = max(54, ceil(bounds.height) + 28)

        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        container.layer?.cornerRadius = 18
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.borderWidth = 2
        container.layer?.borderColor = NSColor(hex: 0xE5E5E5).cgColor

        iconCircle.frame = NSRect(x: 14, y: (height - 30) / 2, width: 30, height: 30)
        iconCircle.layer?.cornerRadius = 10
        iconCircle.layer?.backgroundColor = decoded.tint.withAlphaComponent(0.16).cgColor

        iconView.frame = NSRect(x: 20, y: (height - 18) / 2, width: 18, height: 18)
        let symbol = NSImage(systemSymbolName: decoded.symbol, accessibilityDescription: nil)
        symbol?.isTemplate = true
        iconView.image = symbol
        iconView.contentTintColor = decoded.tint

        label.frame = NSRect(x: 56, y: (height - ceil(bounds.height)) / 2,
                             width: width - 72, height: ceil(bounds.height) + 2)

        guard let screen = currentScreen() else { return }
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY + 96,
                              width: width, height: height),
                       display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func currentScreen() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }) ?? NSScreen.main
    }

    // MARK: - 面板

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let container = NSView()
        container.wantsLayer = true
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.12
        container.layer?.shadowRadius = 10
        container.layer?.shadowOffset = CGSize(width: 0, height: -3)

        let iconCircle = NSView()
        iconCircle.wantsLayer = true
        iconCircle.layer?.cornerRadius = 10
        container.addSubview(iconCircle)

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(iconView)

        let label = NSTextField(wrappingLabelWithString: "")
        label.textColor = NSColor(hex: 0x4B4B4B)
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        container.addSubview(label)

        panel.contentView = container
        self.panel = panel
        self.container = container
        self.iconCircle = iconCircle
        self.iconView = iconView
        self.label = label
        return panel
    }

    // MARK: - 图标

    private struct Decoded {
        let text: String
        let symbol: String
        let tint: NSColor
    }

    private static func decode(_ raw: String) -> Decoded {
        let table: [(String, String, NSColor)] = [
            ("🎤", "mic.fill", NSColor(hex: 0x1899D6)),
            ("✍️", "pencil.line", NSColor(hex: 0x58A700)),
            ("✍", "pencil.line", NSColor(hex: 0x58A700)),
            ("⚡", "bolt.fill", NSColor(hex: 0xE5A800)),
            ("✓", "checkmark", NSColor(hex: 0x58A700)),
            ("✗", "xmark", NSColor(hex: 0xEA2B2B)),
        ]
        for (prefix, symbol, color) in table where raw.hasPrefix(prefix) {
            let rest = String(raw.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Decoded(text: rest, symbol: symbol, tint: color)
        }
        return Decoded(text: raw, symbol: "info.circle.fill", tint: NSColor(hex: 0x58A700))
    }

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
