import Foundation
import CoreGraphics

// MARK: - 可映射的实体键

enum KeymapKeys {
    /// 能进入 CGEventTap 的实体键；语音键由 ATVV 固定处理，音量± 是系统原生键，均不参与映射。
    static let mappable: [RemoteKey] = [
        .power, .tv, .home, .menu, .back, .up, .down, .left, .right, .ok,
    ]

    static func title(_ key: RemoteKey) -> String { key.displayName }

    static func icon(_ key: RemoteKey) -> String {
        switch key {
        case .power: return "power"
        case .tv: return "tv"
        case .home: return "house.fill"
        case .menu: return "line.3.horizontal"
        case .back: return "arrow.uturn.backward"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .ok: return "circle.circle.fill"
        case .voice: return "mic.fill"
        case .volUp: return "speaker.plus.fill"
        case .volDown: return "speaker.minus.fill"
        }
    }
}

// MARK: - 键盘按键

/// 任意 macOS keycode + 修饰键，用系统键盘事件投递。
struct KeyboardShortcut: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64

    var modifierSymbols: String {
        var symbols = ""
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { symbols += "⌃" }
        if flags.contains(.maskAlternate) { symbols += "⌥" }
        if flags.contains(.maskShift) { symbols += "⇧" }
        if flags.contains(.maskCommand) { symbols += "⌘" }
        if flags.contains(.maskSecondaryFn) { symbols += "fn" }
        return symbols
    }

    var displayName: String {
        let key = KeyboardKeyNames.label(for: keyCode)
        let mods = modifierSymbols
        return mods.isEmpty ? key : "\(mods) \(key)"
    }
}

enum KeyboardKeyNames {
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab",
        49: "Space", 50: "`", 51: "Delete", 53: "Escape",
        64: "F17", 65: ".", 67: "*", 69: "+", 71: "Clear", 75: "/", 76: "Enter",
        78: "-", 79: "F18", 80: "F19", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3",
        86: "4", 87: "5", 88: "6", 89: "7", 90: "F20", 91: "8", 92: "9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "Home", 116: "PageUp", 117: "Forward Delete",
        118: "F4", 119: "End", 120: "F2", 121: "PageDown", 122: "F1",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
    ]

    static func label(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}

// MARK: - 按键动作

enum KeyAction: Hashable {
    case volumeUp, volumeDown
    case previousTrack, nextTrack, playPause
    case mute, missionControl
    case escape, displaySleep
    case mode(VoiceMode)
    case layer(String)
    case defaultLayer
    case none
    /// 复用指令系统的动作：打开应用 / 网址 / 运行 Shell / 发送到 DSH。
    case command(CommandAction)
    /// 发送任意键盘按键（Enter / Tab / 方向键 / F 键等）。
    case keyboard(KeyboardShortcut)

    /// 配置里存的稳定标识。
    var id: String {
        switch self {
        case .volumeUp: return "volumeUp"
        case .volumeDown: return "volumeDown"
        case .previousTrack: return "previousTrack"
        case .nextTrack: return "nextTrack"
        case .playPause: return "playPause"
        case .mute: return "mute"
        case .missionControl: return "missionControl"
        case .escape: return "escape"
        case .displaySleep: return "displaySleep"
        case .mode(let mode): return "mode.\(mode.rawValue)"
        case .layer(let id): return "layer.\(id)"
        case .defaultLayer: return "layer.default"
        case .none: return "none"
        case .command(let action):
            guard let data = try? JSONEncoder().encode(action) else { return "cmd:" }
            return "cmd:" + data.base64EncodedString()
        case .keyboard(let shortcut):
            return "key:\(shortcut.keyCode):\(shortcut.modifiers)"
        }
    }

    init?(id: String) {
        switch id {
        case "volumeUp": self = .volumeUp
        case "volumeDown": self = .volumeDown
        case "previousTrack": self = .previousTrack
        case "nextTrack": self = .nextTrack
        case "playPause": self = .playPause
        case "mute": self = .mute
        case "missionControl": self = .missionControl
        case "escape": self = .escape
        case "displaySleep": self = .displaySleep
        case "mode.forward": self = .mode(.forward)
        case "mode.command": self = .mode(.command)
        case "mode.input": self = .mode(.input)
        case "layer.default": self = .defaultLayer
        case "none": self = KeyAction.none
        default:
            if id.hasPrefix("cmd:") {
                guard let data = Data(base64Encoded: String(id.dropFirst("cmd:".count))),
                      let action = try? JSONDecoder().decode(CommandAction.self, from: data) else {
                    return nil
                }
                self = .command(action)
            } else if id.hasPrefix("key:") {
                let parts = id.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 3,
                      let keyCode = UInt16(parts[1]),
                      let modifiers = UInt64(parts[2]) else { return nil }
                self = .keyboard(KeyboardShortcut(keyCode: keyCode, modifiers: modifiers))
            } else if id.hasPrefix("layer.") {
                let layerID = String(id.dropFirst("layer.".count))
                guard !layerID.isEmpty, layerID != KeyLayer.defaultID else { return nil }
                self = .layer(layerID)
            } else {
                return nil
            }
        }
    }

    func title(layers: [KeyLayer]) -> String {
        switch self {
        case .volumeUp: return localized("音量 +")
        case .volumeDown: return localized("音量 −")
        case .previousTrack: return localized("上一首")
        case .nextTrack: return localized("下一首")
        case .playPause: return localized("播放 / 暂停")
        case .mute: return localized("静音")
        case .missionControl: return localized("调度中心")
        case .escape: return localized("Esc（返回）")
        case .displaySleep: return localized("显示器睡眠")
        case .mode(let mode):
            switch mode {
            case .forward: return localized("切到音频输入模式")
            case .command: return localized("切到命令模式")
            case .input: return localized("切到文字输入模式")
            }
        case .layer(let id):
            let name = layers.first(where: { $0.id == id })?.name ?? localized("已删除的层")
            return localized("切换到「%@」", name)
        case .defaultLayer: return localized("回到默认层")
        case .none: return localized("无动作")
        case .command(let action): return action.summary
        case .keyboard(let shortcut): return localized("发送按键 %@", shortcut.displayName)
        }
    }

    var shortTitle: String {
        switch self {
        case .volumeUp: return localized("音量+")
        case .volumeDown: return localized("音量−")
        case .previousTrack: return localized("上一首")
        case .nextTrack: return localized("下一首")
        case .playPause: return localized("播放/暂停")
        case .mute: return localized("静音")
        case .missionControl: return localized("调度中心")
        case .escape: return "Esc"
        case .displaySleep: return localized("睡眠")
        case .mode: return localized("模式")
        case .layer, .defaultLayer: return localized("切层")
        case .none: return localized("无")
        case .command(let action):
            switch action {
            case .openApp: return localized("打开应用")
            case .openURL: return localized("打开网页")
            case .runShell: return "Shell"
            case .sendToDSH: return "DSH"
            }
        case .keyboard: return localized("按键")
        }
    }

    var icon: String {
        switch self {
        case .volumeUp: return "speaker.plus.fill"
        case .volumeDown: return "speaker.minus.fill"
        case .previousTrack: return "backward.fill"
        case .nextTrack: return "forward.fill"
        case .playPause: return "playpause.fill"
        case .mute: return "speaker.slash.fill"
        case .missionControl: return "rectangle.3.group.fill"
        case .escape: return "escape"
        case .displaySleep: return "moon.fill"
        case .mode: return "switch.2"
        case .layer, .defaultLayer: return "square.stack.3d.up.fill"
        case .none: return "slash.circle"
        case .command(let action):
            switch action {
            case .openApp: return "macwindow"
            case .openURL: return "globe"
            case .runShell: return "terminal"
            case .sendToDSH: return "paperplane.fill"
            }
        case .keyboard: return "keyboard"
        }
    }

    var commandAction: CommandAction? {
        if case .command(let action) = self { return action }
        return nil
    }

    var keyboardShortcut: KeyboardShortcut? {
        if case .keyboard(let shortcut) = self { return shortcut }
        return nil
    }

    var isLayerSwitch: Bool {
        switch self {
        case .layer, .defaultLayer: return true
        default: return false
        }
    }

    /// 选择器里的标准动作顺序（层动作由 UI 动态追加）。
    static let standard: [KeyAction] = [
        .volumeUp, .volumeDown, .previousTrack, .nextTrack, .playPause,
        .mute, .missionControl, .escape, .displaySleep,
        .mode(.forward), .mode(.command), .mode(.input),
        .defaultLayer, .none,
    ]
}

// MARK: - 层

struct KeyLayer: Codable, Identifiable, Equatable {
    static let defaultID = "default"

    var id: String
    var name: String
    /// 前台应用 Bundle ID 列表；任一匹配即激活；空数组表示只能手动激活。
    var appBundleIDs: [String]
    /// RemoteKey.rawValue → KeyAction.id；缺省 = 穿透到下一层。
    var bindings: [String: String]

    var isDefault: Bool { id == Self.defaultID }

    /// 兼容旧代码/旧配置的单应用入口：读取第一个，写入时替换整个列表。
    var appBundleID: String? {
        get { appBundleIDs.first }
        set { appBundleIDs = newValue.map { [$0] } ?? [] }
    }

    init(id: String, name: String, appBundleIDs: [String], bindings: [String: String]) {
        self.id = id
        self.name = name
        self.appBundleIDs = Self.normalizedAppIDs(appBundleIDs)
        self.bindings = bindings
    }

    init(id: String, name: String, appBundleID: String?, bindings: [String: String]) {
        self.init(id: id, name: name,
                  appBundleIDs: appBundleID.map { [$0] } ?? [],
                  bindings: bindings)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, appBundleID, appBundleIDs, bindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bindings = try container.decode([String: String].self, forKey: .bindings)
        if let list = try container.decodeIfPresent([String].self, forKey: .appBundleIDs) {
            appBundleIDs = Self.normalizedAppIDs(list)
        } else if let one = try container.decodeIfPresent(String.self, forKey: .appBundleID) {
            appBundleIDs = Self.normalizedAppIDs([one])
        } else {
            appBundleIDs = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bindings, forKey: .bindings)
        if !appBundleIDs.isEmpty {
            try container.encode(appBundleIDs, forKey: .appBundleIDs)
            // 同时写第一个，保证旧版 MyRemote 也能读到触发应用。
            try container.encode(appBundleIDs[0], forKey: .appBundleID)
        }
    }

    private static func normalizedAppIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in ids {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    func action(for key: RemoteKey) -> KeyAction? {
        bindings[key.rawValue].flatMap(KeyAction.init(id:))
    }

    /// 复制为普通层（默认层也会变成可删除/可编辑的普通层）。
    func duplicated(name: String, id: String = UUID().uuidString) -> KeyLayer {
        KeyLayer(id: id, name: name, appBundleIDs: appBundleIDs, bindings: bindings)
    }

    static func makeDefault() -> KeyLayer {
        KeyLayer(id: defaultID, name: localized("默认层"), appBundleIDs: [], bindings: [
            RemoteKey.power.rawValue: KeyAction.displaySleep.id,
            RemoteKey.tv.rawValue: KeyAction.mode(.command).id,
            RemoteKey.home.rawValue: KeyAction.mode(.forward).id,
            RemoteKey.menu.rawValue: KeyAction.mode(.input).id,
            RemoteKey.back.rawValue: KeyAction.escape.id,
            RemoteKey.up.rawValue: KeyAction.volumeUp.id,
            RemoteKey.down.rawValue: KeyAction.volumeDown.id,
            RemoteKey.left.rawValue: KeyAction.previousTrack.id,
            RemoteKey.right.rawValue: KeyAction.nextTrack.id,
            RemoteKey.ok.rawValue: KeyAction.playPause.id,
        ])
    }
}

// MARK: - 解析

struct KeyResolution {
    let action: KeyAction
    let layerID: String
    let layerName: String
}

enum KeymapResolver {

    /// 生效顺序：手动层 → 匹配前台应用的层（按列表顺序）→ 默认层。
    static func activeLayers(_ layers: [KeyLayer], manualID: String?,
                             frontmostBundleID: String?) -> [KeyLayer] {
        var result: [KeyLayer] = []
        var seen = Set<String>()

        if let manualID,
           let manual = layers.first(where: { $0.id == manualID && !$0.isDefault }) {
            result.append(manual)
            seen.insert(manual.id)
        }

        let frontmost = frontmostBundleID?.lowercased()
        for layer in layers where !layer.isDefault {
            guard !seen.contains(layer.id) else { continue }
            let apps = layer.appBundleIDs.map { $0.lowercased() }
            guard !apps.isEmpty else { continue }
            if let frontmost, apps.contains(frontmost) {
                result.append(layer)
                seen.insert(layer.id)
            }
        }

        if let def = layers.first(where: { $0.isDefault }) {
            result.append(def)
        }
        return result
    }

    static func resolve(key: RemoteKey, layers: [KeyLayer], manualID: String?,
                        frontmostBundleID: String?) -> KeyResolution? {
        for layer in activeLayers(layers, manualID: manualID,
                                  frontmostBundleID: frontmostBundleID) {
            if let action = layer.action(for: key) {
                return KeyResolution(action: action, layerID: layer.id, layerName: layer.name)
            }
        }
        return nil
    }
}
