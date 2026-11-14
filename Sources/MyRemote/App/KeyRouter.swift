import Foundation
import CoreGraphics

/// 默认键位（媒体遥控器 + 三模式）。
///
/// | 键 | 动作 |
/// |---|---|
/// | ↑ / ↓ | 音量 + / -（系统媒体键） |
/// | ← / → | 上一首 / 下一首（系统媒体键） |
/// | OK | 播放 / 暂停（系统媒体键） |
/// | 返回 | Esc（关闭弹窗 / 返回） |
/// | 主页 Home | 音频输入模式（只转发麦克风音频） |
/// | TV | 命令模式（语音识别为指令） |
/// | 菜单 Menu | 文字输入模式（语音识别为文字） |
/// | 电源 | 显示器睡眠 |
/// | 音量± | 系统音量（原生） |
/// | 语音 | 语音输入（ATVV 通道驱动） |
final class KeyRouter {

    enum Action: Equatable {
        case volumeUp, volumeDown
        case previousTrack, nextTrack, playPause
        case mute, missionControl
        case escape, displaySleep
        case mode(VoiceMode)
        case layer(String)
        case defaultLayer
        case command(CommandAction)
        case keyboard(KeyboardShortcut)
        case none
    }

    /// 音量类按键的重复节流（系统媒体键无加速度，太密会一次跳太多）。
    private var lastVolumeTime: UInt64 = 0
    private let volumeRepeatInterval: UInt64 = 110_000_000   // 110ms

    var onMode: ((VoiceMode) -> Void)?
    var onLayerAction: ((String?) -> Void)?
    var onCommand: ((CommandAction) -> Void)?
    var onAction: ((Action) -> Void)?
    /// 由层映射解析出的动作；nil 时退回硬编码默认键位。
    var resolveAction: ((RemoteKey) -> KeyAction?)?

    func action(for key: RemoteKey) -> Action {
        switch key {
        case .up, .volUp: return .volumeUp
        case .down, .volDown: return .volumeDown
        case .left: return .previousTrack
        case .right: return .nextTrack
        case .ok: return .playPause
        case .back: return .escape
        case .home: return .mode(.forward)
        case .tv: return .mode(.command)
        case .menu: return .mode(.input)
        case .power: return .displaySleep
        case .voice: return .none
        }
    }

    func handle(_ key: RemoteKey, isRepeat: Bool) {
        let action = resolveAction?(key)?.routerAction ?? action(for: key)

        if isRepeat {
            switch action {
            case .volumeUp, .volumeDown:
                let now = DispatchTime.now().uptimeNanoseconds
                guard now - lastVolumeTime >= volumeRepeatInterval else { return }
                lastVolumeTime = now
            default:
                return
            }
        }

        onAction?(action)
        perform(action)
    }

    private func perform(_ action: Action) {
        switch action {
        case .volumeUp:
            MediaController.post(.volumeUp)
        case .volumeDown:
            MediaController.post(.volumeDown)
        case .previousTrack:
            MediaController.post(.previous)
        case .nextTrack:
            MediaController.post(.next)
        case .playPause:
            MediaController.post(.playPause)
        case .mute:
            MediaController.post(.mute)
        case .missionControl:
            MediaController.postKeyCode(126, flags: .maskControl)  // ⌃↑
        case .escape:
            MediaController.postKeyCode(53)                 // kVK_Escape
        case .displaySleep:
            MediaController.sleepDisplay()
        case .mode(let mode):
            onMode?(mode)
        case .layer(let id):
            onLayerAction?(id)
        case .defaultLayer:
            onLayerAction?(nil)
        case .command(let action):
            onCommand?(action)
        case .keyboard(let shortcut):
            MediaController.postKeyCode(CGKeyCode(shortcut.keyCode),
                                        flags: CGEventFlags(rawValue: shortcut.modifiers))
        case .none:
            break
        }
    }
}


extension KeyAction {
    var routerAction: KeyRouter.Action {
        switch self {
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .previousTrack: return .previousTrack
        case .nextTrack: return .nextTrack
        case .playPause: return .playPause
        case .mute: return .mute
        case .missionControl: return .missionControl
        case .escape: return .escape
        case .displaySleep: return .displaySleep
        case .mode(let mode): return .mode(mode)
        case .layer(let id): return .layer(id)
        case .defaultLayer: return .defaultLayer
        case .command(let action): return .command(action)
        case .keyboard(let shortcut): return .keyboard(shortcut)
        case .none: return .none
        }
    }
}
