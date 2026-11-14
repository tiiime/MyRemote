import Foundation
import SwiftUI

/// 遥控器工作模式。
///
/// - `forward`：音频输入模式，语音只转发到虚拟声卡，不做识别、不输入文字；
/// - `command`：命令模式，语音识别后按指令规则执行；
/// - `input`：文字输入模式，语音识别后粘贴到前台输入框。
enum VoiceMode: String, CaseIterable, Identifiable, Equatable {
    case forward
    case command
    case input

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forward: return localized("音频输入模式")
        case .command: return localized("命令模式")
        case .input: return localized("文字输入模式")
        }
    }

    /// 切换模式时 toast 只报名字：不举例、不重复解释。
    var switchToastText: String { title }

    var shortTitle: String {
        switch self {
        case .forward: return localized("音频输入")
        case .command: return localized("命令")
        case .input: return localized("文字输入")
        }
    }

    var subtitle: String {
        switch self {
        case .forward: return localized("语音只转发到 BlackHole，不做文字输入")
        case .command: return localized("语音识别为指令，命中后自动执行")
        case .input: return localized("语音识别为文字，粘贴到前台输入框")
        }
    }

    /// 只有音频输入模式会把音频转发给其他 App。
    var forwardsAudioToOtherApps: Bool { self == .forward }

    /// 与状态栏角点一致的配色：黄=默认转发，绿=action/命令，蓝=文字输入。
    var tintColor: Color {
        switch self {
        case .forward: return Duo.beeDark
        case .command: return Duo.treeFrog
        case .input: return Duo.whale
        }
    }

    var backgroundColor: Color {
        switch self {
        case .forward: return Duo.beeLight
        case .command: return Duo.seaSponge
        case .input: return Duo.iguana
        }
    }

    var icon: String {
        switch self {
        case .forward: return "dot.radiowaves.left.and.right"
        case .command: return "bolt.fill"
        case .input: return "keyboard.fill"
        }
    }
}
