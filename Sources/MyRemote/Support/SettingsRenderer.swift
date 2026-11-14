import Foundation
import AppKit
import SwiftUI
import CoreGraphics

/// 调试用：把界面离屏渲染成 PNG，便于在没有 GUI 会话时检查排版。
///   MyRemote --render-ui <目录>              渲染全部页面 + 编辑器
///   MyRemote --render-settings <png>         只渲染控制台
///   MyRemote --render-rule-editor <png>      只渲染指令编辑器
enum SettingsRenderer {

    static func renderUI(to directory: String) -> Bool {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppServices.shared.refreshAudioStatusForUI()
        let model = SettingsModel(services: AppServices.shared)
        var ok = true

        for tab in AppTab.allCases where tab != .keymap {
            let view = AppShellView(model: model, tab: tab)
            ok = render(view, size: NSSize(width: 1000, height: 840),
                        to: dir.appendingPathComponent("\(tab.rawValue).png")) && ok
        }
        ok = renderKeymap(to: dir.appendingPathComponent("keymap.png").path) && ok

        let sample = CommandRule(name: "发送到「李白」会话",
                                 phrases: ["我要听李白", "听李白"],
                                 action: .sendToDSH(sessionId: "", sessionTitle: "李白",
                                                    message: "{{text}}"))
        let editor = CommandRuleEditorView(rule: sample, onSave: { _ in }, onCancel: {})
        ok = render(editor, size: NSSize(width: 900, height: 620),
                    to: dir.appendingPathComponent("editor.png")) && ok
        return ok
    }

    static func renderKeyShortcutEditor(to path: String) -> Bool {
        _ = NSApplication.shared
        let view = KeyShortcutEditorView(
            initial: KeyboardShortcut(keyCode: 36,
                                      modifiers: CGEventFlags.maskCommand.rawValue),
            onClose: {}, onSave: { _ in })
        return render(view, size: NSSize(width: 480, height: 500),
                      to: URL(fileURLWithPath: path))
    }

    static func renderKeyCommandEditor(to path: String) -> Bool {
        _ = NSApplication.shared
        let view = KeyCommandEditorView(
            initial: .sendToDSH(sessionId: "", sessionTitle: "李白", message: "播放李白的歌"),
            onClose: {}, onSave: { _ in })
        return render(view, size: NSSize(width: 480, height: 560),
                      to: URL(fileURLWithPath: path))
    }

    static func renderKeymap(to path: String) -> Bool {
        _ = NSApplication.shared
        AppServices.shared.refreshAudioStatusForUI()
        let model = SettingsModel(services: AppServices.shared)

        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "com.apple.finder"
        let appLayer = KeyLayer(id: "app-layer", name: localized("前台应用层"), appBundleID: front, bindings: [
            RemoteKey.ok.rawValue: KeyAction.escape.id,
            RemoteKey.up.rawValue: KeyAction.mode(.command).id,
            RemoteKey.back.rawValue: KeyAction.defaultLayer.id,
            RemoteKey.tv.rawValue: KeyAction.layer("manual-layer").id,
        ])
        let manualLayer = KeyLayer(id: "manual-layer", name: localized("手动层"), appBundleID: nil, bindings: [
            RemoteKey.left.rawValue: KeyAction.previousTrack.id,
            RemoteKey.right.rawValue: KeyAction.nextTrack.id,
            RemoteKey.menu.rawValue: KeyAction.mode(.input).id,
        ])
        model.config.keyLayers = [KeyLayer.makeDefault(), appLayer, manualLayer]
        model.snapshot.frontmostAppBundleID = front
        model.snapshot.manualLayerID = "manual-layer"

        return render(AppShellView(model: model, tab: .keymap),
                      size: NSSize(width: 1000, height: 840),
                      to: URL(fileURLWithPath: path))
    }

    static func renderDashboard(to path: String) -> Bool {
        AppServices.shared.refreshAudioStatusForUI()
        let model = SettingsModel(services: AppServices.shared)
        return render(AppShellView(model: model, tab: .dashboard),
                      size: NSSize(width: 1000, height: 840),
                      to: URL(fileURLWithPath: path))
    }

    static func renderStatusIcons(to path: String) -> Bool {
        _ = NSApplication.shared
        let size = NSSize(width: 420, height: 260)
        let body = StatusIcon.bodyImage()
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            // 浅色菜单栏
            NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
            NSRect(x: 0, y: 135, width: rect.width, height: 125).fill()
            // 深色菜单栏
            NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: rect.width, height: 135).fill()

            for (index, mode) in VoiceMode.allCases.enumerated() {
                let x = 30 + CGFloat(index) * 128
                drawStatusPreview(body: body, mode: mode, color: .black,
                                  origin: NSPoint(x: x, y: 172))
                drawStatusPreview(body: body, mode: mode, color: .white,
                                  origin: NSPoint(x: x, y: 42))
                let label = mode.title as NSString
                label.draw(at: NSPoint(x: x, y: 155),
                           withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                            .foregroundColor: NSColor.darkGray])
                label.draw(at: NSPoint(x: x, y: 20),
                           withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                            .foregroundColor: NSColor.white])
            }
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
        else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }

    private static func drawStatusPreview(body: NSImage, mode: VoiceMode,
                                          color: NSColor, origin: NSPoint) {
        let aspect = body.size.width / max(1, body.size.height)
        let height: CGFloat = 42
        let width = min(74, height * aspect)
        let bodyRect = NSRect(x: origin.x, y: origin.y, width: width, height: height)
        tinted(body, color: color).draw(in: bodyRect)

        let dotSize: CGFloat = 20
        let dotRect = NSRect(x: bodyRect.maxX - dotSize + 2,
                             y: bodyRect.minY - 2,
                             width: dotSize, height: dotSize)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let ring = NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.4, dy: -1.4))
        ring.lineWidth = 2.8
        ring.stroke()
        StatusIcon.badgeColor(for: mode).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(in: NSRect(origin: .zero, size: image.size),
                   from: .zero, operation: .destinationIn, fraction: 1)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    static func renderStatusPanel(to path: String) -> Bool {
        _ = NSApplication.shared
        AppServices.shared.refreshAudioStatusForUI()
        let model = SettingsModel(services: AppServices.shared)
        let view = StatusPanelView(model: model, onClose: {}, onOpenSettings: {})
        return render(view, size: NSSize(width: 336, height: 560),
                      to: URL(fileURLWithPath: path))
    }

    static func renderPermissionGuide(to path: String) -> Bool {
        _ = NSApplication.shared
        let icon: NSImage = {
            let candidates = [
                Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("Resources/AppIcon.icns"),
            ].compactMap { $0 }
            for url in candidates {
                if let image = NSImage(contentsOf: url) { return image }
            }
            return NSImage(systemSymbolName: "playpause.circle.fill", accessibilityDescription: nil)
                ?? NSImage()
        }()
        let model = PermissionGuideModel(kind: .accessibility,
                                         appURL: URL(fileURLWithPath: "/Applications/MyRemote.app"),
                                         appIcon: icon, appName: "MyRemote.app", granted: false)
        model.arrow = .left
        let view = PermissionGuideView(
            model: model,
            onOpenSettings: {}, onNext: {}, onClose: {}, onReveal: {},
            onDragBegan: {}, onDragEnded: { _ in })
        return render(view, size: NSSize(width: 492, height: 330),
                      to: URL(fileURLWithPath: path))
    }

    static func renderRuleEditor(to path: String) -> Bool {
        let sample = CommandRule(name: "发送到「李白」会话",
                                 phrases: ["我要听李白", "听李白"],
                                 action: .sendToDSH(sessionId: "", sessionTitle: "李白",
                                                    message: "{{text}}"))
        let editor = CommandRuleEditorView(rule: sample, onSave: { _ in }, onCancel: {})
        return render(editor, size: NSSize(width: 900, height: 620),
                      to: URL(fileURLWithPath: path))
    }

    // MARK: - 渲染

    private static func render<V: View>(_ view: V, size: NSSize, to url: URL) -> Bool {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        for _ in 0..<14 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            hosting.layoutSubtreeIfNeeded()
        }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            Log.error("渲染界面失败: \(error)")
            return false
        }
    }
}
