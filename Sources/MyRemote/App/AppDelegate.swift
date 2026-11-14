import Foundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var editKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditingShortcuts()

        let services = AppServices.shared
        settingsController = SettingsWindowController(services: services)
        services.showSettingsHandler = { [weak self] in
            self?.settingsController?.show()
        }
        statusItemController = StatusItemController(services: services, openSettings: { [weak self] in
            self?.settingsController?.show()
        })

        if ProcessInfo.processInfo.environment["MYREMOTE_STATUS_PREVIEW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.statusItemController?.showPopoverForPreview()
            }
            return
        }

        if ProcessInfo.processInfo.environment["MYREMOTE_PERMISSION_PREVIEW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                PermissionGuideController.shared.show(.accessibility)
            }
            return
        }

        services.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let editKeyMonitor {
            NSEvent.removeMonitor(editKeyMonitor)
            self.editKeyMonitor = nil
        }
        // 退出时恢复 hidutil 映射，避免遥控器按键留在中转键状态。
        AppServices.shared.stop()
    }

    /// 菜单栏应用没有默认菜单，补上标准快捷键：
    /// ⌘W 关闭窗口、⌘Q 退出、⌘, 打开设置、⌘M 最小化，以及输入框的 ⌘A/C/V/X/Z。
    private func installEditingShortcuts() {
        editKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags
            if flags.contains(.command),
               !flags.contains(.shift),
               !flags.contains(.option),
               !flags.contains(.control) {
                switch event.keyCode {
                case 12: // Q
                    NSApp.terminate(nil)
                    return nil
                case 13: // W
                    NSApp.keyWindow?.performClose(nil)
                    return nil
                case 46: // M
                    NSApp.keyWindow?.performMiniaturize(nil)
                    return nil
                case 43: // ,
                    AppServices.shared.showSettings()
                    return nil
                default:
                    break
                }
            }

            // 快捷键录制框需要捕获包括 ⌘C/⌘V 在内的任意组合，不能在这里吞掉。
            if event.window?.firstResponder is KeyCaptureNSView { return event }
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.option),
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            let selector: Selector?
            switch key {
            case "a": selector = Selector(("selectAll:"))
            case "c": selector = Selector(("copy:"))
            case "v": selector = Selector(("paste:"))
            case "x": selector = Selector(("cut:"))
            case "z":
                selector = event.modifierFlags.contains(.shift)
                    ? Selector(("redo:")) : Selector(("undo:"))
            default:
                selector = nil
            }

            guard let selector else { return event }
            return NSApp.sendAction(selector, to: nil, from: nil) ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
