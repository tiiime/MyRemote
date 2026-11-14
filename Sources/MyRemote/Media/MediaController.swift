import Foundation
import CoreGraphics
import AppKit

/// 系统媒体键（NX_SYSDEFINED）。投递后由系统媒体路由处理：
/// Music / Spotify / 浏览器 / IINA 等支持「正在播放」的 App 都会被控。
enum MediaKey: Int32 {
    case volumeUp = 0
    case volumeDown = 1
    case mute = 7
    case playPause = 16
    case next = 17
    case previous = 18
}

enum MediaController {

    /// 投递一个媒体键（按下 + 抬起）。需要「辅助功能」权限。
    static func post(_ key: MediaKey) {
        postSystemDefined(Int32(key.rawValue))
    }

    private static func postSystemDefined(_ key: Int32) {
        for down in [true, false] {
            let flags = down ? 0xA00 : 0xB00
            let data1 = Int((key << 16) | Int32(flags))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ), let cgEvent = event.cgEvent else { continue }
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    /// 投递普通键盘事件（按键码 + 修饰键）。
    static func postKeyCode(_ keyCode: CGKeyCode, flags: CGEventFlags = [], extraFlags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags.union(extraFlags)
            event.post(tap: .cghidEventTap)
        }
    }

    /// 组合键：先按下修饰键，再按主键（用于 Mission Control 等需要修饰的系统快捷键）。
    static func postCombo(modifiers: [CGKeyCode], key: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for code in modifiers {
            if let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
                event.post(tap: .cghidEventTap)
            }
        }
        for down in [true, false] {
            if let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) {
                if down { event.flags = .maskControl }
                event.post(tap: .cghidEventTap)
            }
        }
        for code in modifiers.reversed() {
            if let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// 让显示器睡眠（等价于按电源键熄屏，可随时唤醒）。
    static func sleepDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
