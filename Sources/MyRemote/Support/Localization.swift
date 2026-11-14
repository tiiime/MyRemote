import Foundation
import AppKit

// MARK: - 查表

/// 以中文原文为 key 查本地化表；缺译文时原样返回中文。
///
/// 之所以用中文原文当 key：现有的 SwiftUI 写法里大量是把字符串当数据传
/// （DuoChip(text:)、VoiceMode.title 等），用原文当 key 可以让这些地方
/// 只加一次 .localized，而不用给每个字面量起英文标识符。
func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 带参数的文案，例如 localized("%lld 条指令", count)。
func localized(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(format, comment: ""), arguments: arguments)
}

extension String {
    /// 把数据源里的中文字面量翻译成当前语言。
    var localized: String { NSLocalizedString(self, comment: "") }
}

// MARK: - 语言偏好

/// 界面语言。切换会写进 AppleLanguages，重启后由系统本地化机制生效。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return localized("跟随系统")
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }

    /// 写进 AppleLanguages 的语言代码；nil 表示跟随系统。
    var preferredCode: String? {
        switch self {
        case .system: return nil
        case .chinese: return "zh-Hans"
        case .english: return "en"
        }
    }

    static let defaultsKey = "MyRemoteLanguage"

    static var current: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system }
        set { apply(newValue) }
    }

    /// 当前真正生效的语言（跟随系统时需要问一下 Bundle）。
    static var effective: AppLanguage {
        let code = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        return code.hasPrefix("zh") ? .chinese : .english
    }

    static func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: defaultsKey)
        if let code = language.preferredCode {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        defaults.synchronize()
    }
}

// MARK: - 重启

enum AppRelauncher {
    /// 重新拉起自己，用于让语言切换生效；开发态（裸二进制）只退出。
    static func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else {
            NSApp.terminate(nil)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
