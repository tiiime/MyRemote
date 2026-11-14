import Foundation

/// 应用配置（~/Library/Application Support/MyRemote/config.json）。
/// 只放真正需要用户改的项；键位默认值在 KeyLayer.makeDefault() 里。
/// 自定义解码：缺失字段一律取默认值，保证旧版 config.json 平滑升级。
struct AppConfig: Codable, Equatable {
    /// v8：默认指令「打开 DeepSeek Harness」更名为「打开大肥鱼」并补充别名。
    static let currentVersion = 8

    var version = AppConfig.currentVersion

    /// 识别语言：auto / zh / en / ja / ko / yue
    var language = "auto"
    /// 是否启用逆文本归一化（数字、标点更自然）。
    var useItn = true
    /// 识别完成后自动粘贴到前台输入框（指令模式下不粘贴，改为匹配指令）。
    var autoPaste = true
    /// 屏幕底部浮动提示。
    var showToast = true
    /// 是否把识别文本写进日志（默认关：日志只记时长、语言和字数）。
    var logTranscripts = false
    /// 模型仓库（HuggingFace）。
    var modelRepo = "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
    /// HuggingFace 直连失败时的镜像（留空则只用主站）。
    var hfMirror = "https://hf-mirror.com"

    /// 指令模式下「语音 → 指令」的匹配规则（按数组顺序，先命中先用）。
    var commandRules: [CommandRule] = CommandRule.defaults

    /// 是否把遥控器语音同时输出到虚拟声卡，供其他 App 当麦克风使用。
    /// 默认开启：音频输入模式就是「只做麦克风音频转发」。
    var shareVoiceToBlackHole = true
    /// 模式切换音效。
    var modeSoundsEnabled = true
    /// 虚拟声卡设备名前缀。
    var blackHoleDeviceName = "BlackHole 2ch"

    /// 按键映射层；default 层永远存在并作为兜底。
    var keyLayers: [KeyLayer] = [KeyLayer.makeDefault()]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, language, useItn, autoPaste, showToast, modelRepo, hfMirror, logTranscripts
        case commandRules
        case shareVoiceToBlackHole, blackHoleDeviceName, modeSoundsEnabled
        case keyLayers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        useItn = try container.decodeIfPresent(Bool.self, forKey: .useItn) ?? true
        autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? true
        showToast = try container.decodeIfPresent(Bool.self, forKey: .showToast) ?? true
        logTranscripts = try container.decodeIfPresent(Bool.self, forKey: .logTranscripts) ?? false
        modelRepo = try container.decodeIfPresent(String.self, forKey: .modelRepo)
            ?? "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
        hfMirror = try container.decodeIfPresent(String.self, forKey: .hfMirror) ?? "https://hf-mirror.com"
        commandRules = try container.decodeIfPresent([CommandRule].self, forKey: .commandRules)
            ?? CommandRule.defaults
        shareVoiceToBlackHole = try container.decodeIfPresent(Bool.self, forKey: .shareVoiceToBlackHole) ?? true
        blackHoleDeviceName = try container.decodeIfPresent(String.self, forKey: .blackHoleDeviceName)
            ?? "BlackHole 2ch"
        modeSoundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .modeSoundsEnabled) ?? true
        var layers = try container.decodeIfPresent([KeyLayer].self, forKey: .keyLayers)
            ?? [KeyLayer.makeDefault()]
        if !layers.contains(where: { $0.isDefault }) {
            layers.insert(KeyLayer.makeDefault(), at: 0)
        }
        keyLayers = layers
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(language, forKey: .language)
        try container.encode(useItn, forKey: .useItn)
        try container.encode(autoPaste, forKey: .autoPaste)
        try container.encode(showToast, forKey: .showToast)
        try container.encode(logTranscripts, forKey: .logTranscripts)
        try container.encode(modelRepo, forKey: .modelRepo)
        try container.encode(hfMirror, forKey: .hfMirror)
        try container.encode(commandRules, forKey: .commandRules)
        try container.encode(shareVoiceToBlackHole, forKey: .shareVoiceToBlackHole)
        try container.encode(blackHoleDeviceName, forKey: .blackHoleDeviceName)
        try container.encode(modeSoundsEnabled, forKey: .modeSoundsEnabled)
        try container.encode(keyLayers, forKey: .keyLayers)
    }
}

enum ConfigStore {

    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyRemote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL { directory.appendingPathComponent("config.json") }

    /// 模型目录：优先环境变量（开发/测试用），否则 Application Support。
    static var modelDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MYREMOTE_MODEL_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return directory.appendingPathComponent("Models/sensevoice", isDirectory: true)
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        guard decoded.version < AppConfig.currentVersion else { return decoded }
        let migrated = migrate(decoded)
        _ = save(migrated)
        return migrated
    }

    /// 配置迁移：v2 → v3 补齐「发送到 DSH 会话」预置规则（只补一次，用户删除后不会反复加回）。
    static func migrate(_ input: AppConfig) -> AppConfig {
        var config = input
        if config.version < 3 {
            if !config.commandRules.contains(where: { $0.isSendToDSH }),
               let rule = CommandRule.defaults.first(where: { $0.isSendToDSH }) {
                config.commandRules.append(rule)
            }
            config.version = 3
        }
        if config.version < 4 {
            config.version = 4
        }
        if config.version < 5 {
            // 新模式以「音频转发」为默认，升级时补开共享（只迁移一次）。
            config.shareVoiceToBlackHole = true
            config.version = 5
        }
        if config.version < 6 {
            config.version = 6
        }
        if config.version < 7 {
            if !config.keyLayers.contains(where: { $0.isDefault }) {
                config.keyLayers.insert(KeyLayer.makeDefault(), at: 0)
            }
            config.version = 7
        }
        if config.version < 8 {
            if let index = config.commandRules.firstIndex(where: {
                $0.name == "打开 DeepSeek Harness"
                    && $0.action == .openApp(bundleID: "com.deepseek.dsh")
            }) {
                var rule = config.commandRules[index]
                rule.name = "打开大肥鱼"
                for alias in CommandRule.defaults.first?.phrases ?? []
                where !rule.phrases.contains(alias) {
                    rule.phrases.append(alias)
                }
                config.commandRules[index] = rule
            }
            config.version = 8
        }
        return config
    }

    @discardableResult
    static func save(_ config: AppConfig) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return false }
        do {
            try data.write(to: configURL, options: .atomic)
            return true
        } catch {
            Log.error("配置写入失败: \(error)")
            return false
        }
    }
}
