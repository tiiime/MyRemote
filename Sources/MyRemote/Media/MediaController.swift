import Foundation
import CoreGraphics
import AppKit
import Carbon

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

    /// 投递键盘事件（按键码 + 修饰键）。
    static func postKeyCode(_ keyCode: CGKeyCode, flags: CGEventFlags = [], extraFlags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let shortcutFlags = flags.union(extraFlags)
        let heldFlags = keyCode == kVK_Tab && shortcutFlags.contains(.maskCommand)
            ? CGEventSource.flagsState(.hidSystemState) : []
        for event in keyEvents(keyCode, flags: shortcutFlags, heldFlags: heldFlags, source: source) {
            event.post(tap: .cghidEventTap)
        }
    }

    static func keyEvents(_ keyCode: CGKeyCode, flags: CGEventFlags, heldFlags: CGEventFlags,
                          source: CGEventSource) -> [CGEvent] {
        // ⌘Tab 的切换器在 Command 松开时才确认；只有 Tab 上的 ⌘ 标记不够。
        // 如果用户已经按着 Command，不替用户松开它。
        let isAppSwitch = keyCode == kVK_Tab && flags.contains(.maskCommand)
        let synthesizeCommand = isAppSwitch && !heldFlags.contains(.maskCommand)
        let leftCommand = CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK)).union(.maskCommand)
        var keyFlags = isAppSwitch ? flags.union(heldFlags) : flags
        if synthesizeCommand { keyFlags.formUnion(leftCommand) }
        var steps: [(code: CGKeyCode, down: Bool, flags: CGEventFlags)] = [
            (keyCode, true, keyFlags), (keyCode, false, keyFlags),
        ]
        if synthesizeCommand {
            let command = CGKeyCode(kVK_Command)
            steps.insert((command, true, heldFlags.union(leftCommand)), at: 0)
            steps.append((command, false, heldFlags))
        }

        var events: [CGEvent] = []
        for step in steps {
            // 先创建整组再投递，避免只发了 Command 按下、没发松开。
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: step.code, keyDown: step.down)
            else { return [] }
            event.flags = step.flags
            events.append(event)
        }
        return events
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
