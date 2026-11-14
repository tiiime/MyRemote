import Foundation
import AppKit
import ApplicationServices

/// 把识别出的文字投递到当前焦点输入框。
/// 策略：剪贴板 + ⌘V（对原生 App / 浏览器 / Electron 都可靠），随后恢复原剪贴板。
enum TextInjector {

    enum Result {
        case pasted
        case copied        // 自动粘贴关闭或没有辅助功能权限时，只复制到剪贴板
        case failed(String)
    }

    static func deliver(_ text: String, autoPaste: Bool) -> Result {
        guard !text.isEmpty else { return .failed("空文本") }
        let pasteboard = NSPasteboard.general

        guard autoPaste else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copied
        }

        guard AXIsProcessTrusted() else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copied
        }

        // 保存原剪贴板（含图片/文件等非文本内容），粘贴后按 changeCount 判断是否恢复，
        // 避免覆盖用户期间新复制的内容。
        let saved = captureClipboard()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount

        // 给剪贴板一点落地时间，再投递 ⌘V。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MediaController.postKeyCode(9, flags: .maskCommand)   // kVK_ANSI_V
        }

        if let saved {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard NSPasteboard.general.changeCount == ours else { return }
                restoreClipboard(saved)
            }
        }
        return .pasted
    }

    // MARK: - 剪贴板快照

    private struct ItemSnapshot {
        var entries: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    private static func captureClipboard() -> [ItemSnapshot]? {
        guard let items = NSPasteboard.general.pasteboardItems else { return nil }
        var snapshots: [ItemSnapshot] = []
        for item in items {
            var entries: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    entries.append((type, data))
                }
            }
            if !entries.isEmpty { snapshots.append(ItemSnapshot(entries: entries)) }
        }
        return snapshots
    }

    private static func restoreClipboard(_ snapshots: [ItemSnapshot]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshots.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in snapshot.entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    /// 权限状态（供设置页展示）。
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
