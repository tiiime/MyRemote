import Foundation
import AppKit
import SwiftUI

/// 设置窗口宿主。
final class SettingsWindowController {

    private let services: AppServices
    private var window: NSWindow?
    private var model: SettingsModel?

    init(services: AppServices) {
        self.services = services
    }

    func show() {
        if window == nil {
            let model = SettingsModel(services: services)
            self.model = model
            let hosting = NSHostingView(rootView: AppShellView(model: model))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 840),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MyRemote"
            window.minSize = NSSize(width: 960, height: 760)
            window.backgroundColor = NSColor.white
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
