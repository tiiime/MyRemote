import Foundation
import Carbon
import CoreGraphics
import CryptoKit

/// 内置自检：`MyRemote --self-test`。
/// 不依赖遥控器与模型，验证纯逻辑（ADPCM / 帧重组 / 映射表 / 配置 / WAV）。
enum SelfTest {

    private static var failures = 0
    private static var checks = 0

    static func run() -> Bool {
        failures = 0
        checks = 0

        testADPCM()
        testFrameAccumulator()
        testKeyRemapParsing()
        testKeyTables()
        testKeyRouter()
        testKeymapLayers()
        testKeyCommandActions()
        testKeyboardShortcuts()
        testKeyboardEvents()
        testModeKeyMapping()
        testStatusIcons()
        testPermissionGuide()
        testLayerDuplication()
        testCommandMatching()
        testCommandDefaultsAndMigration()
        testCommandRoundtrip()
        testTemplateRender()
        testCookieSigning()
        testConfigRoundtrip()
        testLegacyConfigDecoding()
        testModelURLs()
        testTextCleanup()
        testWavReader()
        testWebRemotePage()

        print("self-test: \(checks - failures)/\(checks) passed")
        return failures == 0
    }

    // MARK: - 用例

    private static func testADPCM() {
        let decoder = ADPCMDecoder()
        let zeros = decoder.decode(Data([0x00, 0x00]))
        expect(zeros == [0, 0, 0, 0], "ADPCM 静音解码为 0")

        let decoder2 = ADPCMDecoder()
        decoder2.reset(predictor: 1000, stepIndex: 20)
        let decoded = decoder2.decode(Data([0x7F, 0x80]))
        expect(decoded.count == 4, "ADPCM 每字节解 2 个样本")
        expect(decoded.allSatisfy { $0 != 0 }, "非零步长输出非零样本")
    }

    private static func testFrameAccumulator() {
        var accumulator = FrameAccumulator(frameSize: 4)
        var frames = accumulator.append(Data([1, 2, 3, 4, 5]))
        expect(frames == [Data([1, 2, 3, 4])], "帧重组切出整帧")
        frames = accumulator.append(Data([6, 7, 8]))
        expect(frames == [Data([5, 6, 7, 8])], "跨包残帧拼接")
        accumulator.reset()
        frames = accumulator.append(Data([9]))
        expect(frames.isEmpty, "reset 后丢弃残帧")
    }

    private static func testKeyRemapParsing() {
        expect(KeyRemapper.parseUserKeyMapping("")?.isEmpty == true, "空输出解析为空数组")
        expect(KeyRemapper.parseUserKeyMapping("(null)")?.isEmpty == true, "(null) 解析为空数组")
        let plist = """
        {
            "HIDKeyboardModifierMappingSrc" = 0x700000052;
            "HIDKeyboardModifierMappingDst" = 0x70000006E;
        },
        {
            "HIDKeyboardModifierMappingSrc" = 0x700000050;
            "HIDKeyboardModifierMappingDst" = 0x700000068;
        }
        """
        let pairs = KeyRemapper.parseUserKeyMapping(plist)
        expect(pairs?.count == 2, "plist 映射解析出 2 条")
        expect(pairs?.first?.src == 0x700000052 && pairs?.first?.dst == 0x70000006E, "首条映射值正确")
        expect(KeyRemapper.parseUserKeyMapping("garbage") == nil, "无法识别时返回 nil")
    }

    private static func testKeyTables() {
        expect(RemoteKey.usageMap.count == 13, "13 个物理键的 usage 表完整")
        let keycodes = KeyRemapper.keycodeMap
        expect(keycodes[79] == .ok, "OK 中转键码映射正确")
        expect(keycodes[80] == .up && keycodes[90] == .down, "方向键码映射正确")
        expect(Set(KeyRemapper.keycodeMap.values).count == KeyRemapper.table.count, "无键码冲突")
    }

    private static func testKeyRouter() {
        let router = KeyRouter()
        expect(router.action(for: .ok) == .playPause, "OK = 播放/暂停")
        expect(router.action(for: .up) == .volumeUp && router.action(for: .down) == .volumeDown, "↑↓ = 音量")
        expect(router.action(for: .left) == .previousTrack && router.action(for: .right) == .nextTrack,
               "←→ = 上一首/下一首")
        expect(router.action(for: .back) == .escape, "返回 = Esc")
        expect(router.action(for: .voice) == .none, "语音键交给 ATVV")

        var switched: [String?] = []
        router.onLayerAction = { switched.append($0) }
        router.resolveAction = { key in key == .ok ? .layer("game") : nil }
        router.handle(.ok, isRepeat: false)
        router.resolveAction = { key in key == .ok ? .defaultLayer : nil }
        router.handle(.ok, isRepeat: false)
        expect(switched == ["game", nil], "按键可触发切层 / 回默认层")
    }

    private static func testKeymapLayers() {
        let def = KeyLayer.makeDefault()
        expect(def.action(for: .ok) == .playPause, "默认层 OK = 播放/暂停")
        expect(def.action(for: .home) == .mode(.forward), "默认层 Home = 音频输入模式")
        expect(def.action(for: .up) == .volumeUp, "默认层 ↑ = 音量+")

        let game = KeyLayer(id: "game", name: "游戏", appBundleID: nil, bindings: [
            RemoteKey.ok.rawValue: KeyAction.escape.id,
            RemoteKey.tv.rawValue: KeyAction.layer("game").id,
        ])
        let layers = [def, game]

        let manual = KeymapResolver.resolve(key: .ok, layers: layers,
                                            manualID: "game", frontmostBundleID: nil)
        expect(manual?.action == .escape && manual?.layerID == "game", "手动层覆盖默认层")

        let passThrough = KeymapResolver.resolve(key: .up, layers: layers,
                                                 manualID: "game", frontmostBundleID: nil)
        expect(passThrough?.action == .volumeUp && passThrough?.layerID == KeyLayer.defaultID,
               "层未绑定按键时穿透到默认层")

        let browser = KeyLayer(id: "browser", name: "浏览器", appBundleID: "com.apple.Safari", bindings: [
            RemoteKey.ok.rawValue: KeyAction.none.id,
        ])
        let appLayers = [def, browser]
        let appActive = KeymapResolver.resolve(key: .ok, layers: appLayers,
                                               manualID: nil, frontmostBundleID: "com.apple.Safari")
        expect(appActive?.action == KeyAction.none && appActive?.layerID == "browser",
               "前台应用层自动激活")

        let appInactive = KeymapResolver.resolve(key: .ok, layers: appLayers,
                                                 manualID: nil, frontmostBundleID: "com.apple.Xcode")
        expect(appInactive?.action == .playPause && appInactive?.layerID == KeyLayer.defaultID,
               "应用不在前台时回退默认层")

        let multi = KeyLayer(id: "multi", name: "多应用", appBundleIDs: [
            "com.apple.Safari", "com.apple.Xcode",
        ], bindings: [RemoteKey.ok.rawValue: KeyAction.none.id])
        let multiLayers = [def, multi]
        for bundle in ["com.apple.Safari", "com.apple.Xcode"] {
            let result = KeymapResolver.resolve(key: .ok, layers: multiLayers,
                                                manualID: nil, frontmostBundleID: bundle)
            expect(result?.action == KeyAction.none && result?.layerID == "multi",
                   "多应用触发：\(bundle) 前台时激活")
        }
        let multiInactive = KeymapResolver.resolve(key: .ok, layers: multiLayers,
                                                   manualID: nil, frontmostBundleID: "com.apple.Terminal")
        expect(multiInactive?.layerID == KeyLayer.defaultID, "多应用都不在前台时回退默认层")

        let legacyLayer = """
        {"id":"legacy","name":"旧单应用层","appBundleID":"com.apple.Safari","bindings":{}}
        """
        let decodedLegacy = try! JSONDecoder().decode(KeyLayer.self, from: Data(legacyLayer.utf8))
        expect(decodedLegacy.appBundleIDs == ["com.apple.Safari"], "旧单应用配置迁移成数组")

        let multiLayer = KeyLayer(id: "roundtrip", name: "多应用",
                                  appBundleIDs: ["com.apple.Safari", "com.apple.Xcode"],
                                  bindings: [:])
        let multiData = try! JSONEncoder().encode(multiLayer)
        let decodedMulti = try! JSONDecoder().decode(KeyLayer.self, from: multiData)
        expect(decodedMulti.appBundleIDs == multiLayer.appBundleIDs, "多应用触发条件 JSON 往返")

        expect(KeyAction(id: "mode.input") == .mode(.input), "动作 ID 往返：模式")
        expect(KeyAction(id: "layer.game") == .layer("game"), "动作 ID 往返：层")
        expect(KeyAction(id: "none") == KeyAction.none, "动作 ID 往返：无动作")
        expect(KeyAction(id: "layer.default") == .defaultLayer, "动作 ID 往返：默认层")
    }

    private static func testKeyCommandActions() {
        let commands: [CommandAction] = [
            .openApp(bundleID: "com.apple.Safari"),
            .openURL("https://example.com/a?b=1"),
            .runShell("echo hi && ls"),
            .sendToDSH(sessionId: "s1", sessionTitle: "李白", message: "测试"),
        ]
        for command in commands {
            let action = KeyAction.command(command)
            expect(KeyAction(id: action.id) == action,
                   "按键指令动作往返：\(command.summary)")
        }

        let router = KeyRouter()
        var received: CommandAction?
        router.onCommand = { received = $0 }
        router.resolveAction = { _ in .command(.openURL("https://example.com")) }
        router.handle(.ok, isRepeat: false)
        expect(received == .openURL("https://example.com"), "按键触发指令动作")

        expect(KeyAction.mute.routerAction == .mute, "静音动作可映射")
        expect(KeyAction.missionControl.routerAction == .missionControl, "调度中心动作可映射")
    }

    private static func testKeyboardShortcuts() {
        let plain = KeyboardShortcut(keyCode: 36, modifiers: 0)
        expect(plain.displayName == "Return", "回车键名称")
        expect(KeyboardKeyNames.label(for: 123) == "Left", "方向键 keycode 名称")
        expect(KeyboardKeyNames.label(for: 999) == "Key 999", "未知 keycode 回退")

        let cmdReturn = KeyboardShortcut(keyCode: 36,
                                         modifiers: CGEventFlags.maskCommand.rawValue)
        expect(cmdReturn.displayName.contains("⌘") && cmdReturn.displayName.contains("Return"),
               "组合键显示修饰符")

        let action = KeyAction.keyboard(cmdReturn)
        expect(KeyAction(id: action.id) == action, "键盘按键动作 ID 往返")
        expect(KeyAction(id: "key:53:0") == .keyboard(KeyboardShortcut(keyCode: 53, modifiers: 0)),
               "Esc keycode 解析")
        expect(action.routerAction == .keyboard(cmdReturn), "键盘动作映射到路由")
        expect(KeyAction(id: "key:not-a-number:0") == nil, "非法 keycode 拒绝")
    }

    private static func testKeyboardEvents() {
        guard let source = CGEventSource(stateID: .privateState) else {
            expect(false, "能创建键盘事件源")
            return
        }
        let tab = CGKeyCode(kVK_Tab)
        let command = CGKeyCode(kVK_Command)
        let forward = MediaController.keyEvents(tab, flags: .maskCommand, heldFlags: [], source: source)
        expect(forward.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged],
               "⌘Tab 发送完整的修饰键按下和松开事件")
        expect(forward.map { $0.getIntegerValueField(.keyboardEventKeycode) } ==
               [command, tab, tab, command].map(Int64.init), "⌘Tab 按 Command、Tab、Tab、Command 排序")
        expect(forward.map { $0.flags.contains(.maskCommand) } == [true, true, true, false],
               "⌘Tab 在最后一个事件清除 Command 标记")

        let backward = MediaController.keyEvents(tab, flags: [.maskCommand, .maskShift],
                                                 heldFlags: [], source: source)
        expect(backward.map { $0.flags.contains(.maskShift) } == [false, true, true, false],
               "⌘⇧Tab 保留 Tab 上的 Shift 标记")

        let heldCommand: CGEventFlags = [.maskCommand, .init(rawValue: UInt64(NX_DEVICERCMDKEYMASK))]
        let alreadyHeld = MediaController.keyEvents(tab, flags: .maskCommand,
                                                   heldFlags: heldCommand, source: source)
        expect(alreadyHeld.map(\.type) == [.keyDown, .keyUp] && alreadyHeld.map(\.flags) == [heldCommand, heldCommand],
               "⌘Tab 不松开用户已按住的 Command")
        let plain = MediaController.keyEvents(tab, flags: [], heldFlags: [], source: source)
        let paste = MediaController.keyEvents(CGKeyCode(kVK_ANSI_V), flags: .maskCommand,
                                              heldFlags: [], source: source)
        expect(plain.map(\.type) == [.keyDown, .keyUp] && plain.map(\.flags) == [[], []],
               "普通 Tab 事件不变")
        expect(paste.map(\.type) == [.keyDown, .keyUp] && paste.map(\.flags) == [.maskCommand, .maskCommand],
               "⌘V 事件不变")
    }

    private static func testModeKeyMapping() {
        let router = KeyRouter()
        expect(router.action(for: .home) == .mode(.forward), "Home = 音频输入模式")
        expect(router.action(for: .tv) == .mode(.command), "TV = 命令模式")
        expect(router.action(for: .menu) == .mode(.input), "Menu = 文字输入模式")

        var received: [VoiceMode] = []
        router.onMode = { received.append($0) }
        router.handle(.tv, isRepeat: false)
        router.handle(.home, isRepeat: false)
        router.handle(.menu, isRepeat: false)
        expect(received == [.command, .forward, .input], "模式键回调顺序正确")
        expect(VoiceMode.forward.forwardsAudioToOtherApps, "音频输入模式允许音频转发")
        expect(!VoiceMode.command.forwardsAudioToOtherApps, "命令模式不转发音频")
        expect(!VoiceMode.input.forwardsAudioToOtherApps, "文字输入模式不转发音频")
    }

    private static func testStatusIcons() {
        let body = StatusIcon.bodyImage()
        expect(body.size.width > 0 && body.size.height > 0, "状态栏主体图标非空")
        expect(!StatusIcon.badgeColor(for: .forward).isEqual(StatusIcon.badgeColor(for: .command)),
               "默认与命令模式角点颜色不同")
        expect(!StatusIcon.badgeColor(for: .command).isEqual(StatusIcon.badgeColor(for: .input)),
               "命令与文字输入模式角点颜色不同")
    }

    private static func testPermissionGuide() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 492, height: 262)
        let settings = CGRect(x: 400, y: 200, width: 800, height: 600)
        let frame = PermissionGuidePlacement.frame(settings: settings, visible: visible, size: size)
        expect(frame.minX >= settings.maxX, "引导窗优先贴在设置窗口右侧")
        expect(visible.contains(frame), "引导窗限制在屏幕可见范围内")

        let nearEdge = CGRect(x: 1200, y: 200, width: 700, height: 600)
        let left = PermissionGuidePlacement.frame(settings: nearEdge, visible: visible, size: size)
        expect(left.maxX <= nearEdge.minX, "右侧放不下时贴左侧")

        expect(PermissionKind.accessibility.paneURL.contains("Privacy_Accessibility"),
               "辅助功能面板 URL 正确")
        expect(PermissionKind.inputMonitoring.paneURL.contains("Privacy_ListenEvent"),
               "输入监控面板 URL 正确")
        expect(PermissionKind.inputMonitoring.next == nil,
               "输入监控之后没有下一步")
    }

    private static func testCommandDefaultsAndMigration() {
        let aliases = [
            "打开dsh", "启动dsh", "切换到dsh", "dsh", "deepseekharness",
            "打开deepseek", "打开大肥鱼", "打开大飞云", "打开大飞鱼",
        ]
        let def = CommandRule.defaults.first
        expect(def?.name == "打开大肥鱼", "默认指令标题为「打开大肥鱼」")
        expect(def?.action == .openApp(bundleID: "com.deepseek.dsh"), "默认指令仍打开 DSH")
        for alias in aliases {
            expect(def?.phrases.contains(alias) == true, "默认指令包含别名：\(alias)")
        }

        var config = AppConfig()
        config.version = 7
        config.commandRules = [
            CommandRule(name: "打开 DeepSeek Harness",
                        phrases: ["打开dsh", "dsh"],
                        action: .openApp(bundleID: "com.deepseek.dsh")),
        ]
        let migrated = ConfigStore.migrate(config)
        let rule = migrated.commandRules.first
        expect(migrated.version == 8, "配置迁移到 v8")
        expect(rule?.name == "打开大肥鱼", "旧默认规则更名为「打开大肥鱼」")
        for alias in aliases {
            expect(rule?.phrases.contains(alias) == true, "迁移后包含别名：\(alias)")
        }
    }

    private static func testLayerDuplication() {
        let source = KeyLayer(
            id: "source", name: "剪辑", appBundleID: "com.example.editor",
            bindings: [RemoteKey.ok.rawValue: KeyAction.playPause.id]
        )
        let copy = source.duplicated(name: "剪辑 副本", id: "copy")
        expect(copy.id == "copy", "复制层使用新 ID")
        expect(copy.name == "剪辑 副本", "复制层使用新名称")
        expect(copy.bindings == source.bindings, "复制层完整复制绑定")
        expect(copy.appBundleID == "com.example.editor", "复制层保留应用触发条件")
        expect(!copy.isDefault, "复制层不是默认层")

        let defaultCopy = KeyLayer.makeDefault().duplicated(name: "默认层 副本", id: "default-copy")
        expect(!defaultCopy.isDefault, "默认层复制后变成普通层")
        expect(defaultCopy.bindings == KeyLayer.makeDefault().bindings, "默认层复制保留全部绑定")
    }

    private static func testCommandMatching() {
        let rule = CommandRule(name: "dsh", phrases: ["打开 dsh", "dsh"],
                               action: .openApp(bundleID: "com.deepseek.dsh"))
        expect(CommandMatcher.firstMatch("请帮我打开 DSH", rules: [rule]) != nil,
               "忽略大小写/空格/前后缀")
        expect(CommandMatcher.firstMatch("打开音乐", rules: [rule]) == nil, "无关文本不匹配")

        let exact = CommandRule(name: "exact", phrases: ["打开dsh"],
                                action: .openApp(bundleID: ""), matchMode: .exact)
        expect(CommandMatcher.matches("打开 DSH。", rule: exact), "完全一致模式归一化后匹配")
        expect(!CommandMatcher.matches("请打开dsh", rule: exact), "完全一致模式不接受多余内容")

        var disabled = rule
        disabled.enabled = false
        expect(CommandMatcher.firstMatch("打开dsh", rules: [disabled]) == nil, "停用指令不参与匹配")
    }

    private static func testCommandRoundtrip() {
        let rule = CommandRule(name: "打开 DSH",
                               phrases: ["打开dsh"],
                               action: .openApp(bundleID: "com.deepseek.dsh"),
                               matchMode: .contains, enabled: true)
        let data = try! JSONEncoder().encode(rule)
        let decoded = try! JSONDecoder().decode(CommandRule.self, from: data)
        expect(decoded == rule, "打开应用指令 JSON 往返一致")

        let dsh = CommandRule(name: "发送到李白",
                              phrases: ["我要听李白"],
                              action: .sendToDSH(sessionId: "", sessionTitle: "李白",
                                                 message: "{{text}}"))
        let dshData = try! JSONEncoder().encode(dsh)
        let dshDecoded = try! JSONDecoder().decode(CommandRule.self, from: dshData)
        expect(dshDecoded == dsh, "发送到 DSH 指令 JSON 往返一致")
    }

    private static func testTemplateRender() {
        expect(CommandRunner.renderMessage(template: "", input: "hello") == "hello",
               "空模板直接发送识别文本")
        expect(CommandRunner.renderMessage(template: "{{text}}", input: "我要听李白") == "我要听李白",
               "{{text}} 占位符替换")
        expect(CommandRunner.renderMessage(template: "请处理：{{text}}", input: "x") == "请处理：x",
               "模板前后缀保留")
        expect(CommandRunner.renderMessage(template: "固定命令", input: "x") == "固定命令",
               "无占位符时发送固定文本")
    }

    private static func testCookieSigning() {
        let secret = Data(repeating: 7, count: 32)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cookie = DSHCredential.makeBrowserCookie(secret: secret,
                                                      authority: "127.0.0.1:53932",
                                                      now: now)
        expect(cookie.hasPrefix("dsh-auth-"), "Cookie 名称前缀")

        guard let eq = cookie.firstIndex(of: "=") else {
            expect(false, "Cookie 带等号")
            return
        }
        let value = String(cookie[cookie.index(after: eq)...])
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        expect(parts.count == 3 && parts[0] == "v1", "Cookie 版本与三段式")

        guard parts.count == 3 else { return }
        let body = String(parts[1])
        let mac = HMAC<SHA256>.authenticationCode(for: Data(body.utf8),
                                                  using: SymmetricKey(data: secret))
        expect(DSHCredential.base64URL(Data(mac)) == String(parts[2]), "Cookie 签名可用密钥验证")

        if let payloadData = DSHCredential.base64URLDecode(body),
           let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            expect(payload["authority"] as? String == "127.0.0.1:53932", "Cookie 绑定 authority")
            expect(payload["version"] as? Int == 1, "Cookie 载荷版本为 1")
        } else {
            expect(false, "Cookie 载荷可解析")
        }
    }

    private static func testConfigRoundtrip() {
        var config = AppConfig()
        config.language = "zh"
        config.autoPaste = false
        config.shareVoiceToBlackHole = true
        config.keyLayers.append(KeyLayer(
            id: "test-layer", name: "测试层", appBundleID: "com.apple.Safari",
            bindings: [RemoteKey.ok.rawValue: KeyAction.layer("test-layer").id]
        ))
        let data = try! JSONEncoder().encode(config)
        let decoded = try! JSONDecoder().decode(AppConfig.self, from: data)
        expect(decoded == config, "配置 JSON 往返一致")
    }

    private static func testLegacyConfigDecoding() {
        let legacy = """
        {"version":1,"language":"zh","useItn":true,"autoPaste":true,"showToast":true,
         "modelRepo":"csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
         "hfMirror":"https://hf-mirror.com"}
        """
        let config = try? JSONDecoder().decode(AppConfig.self, from: Data(legacy.utf8))
        expect(config?.commandRules.count == CommandRule.defaults.count, "旧配置补齐默认指令")
        expect(config?.language == "zh", "旧配置已有字段保留")
        expect(config?.modeSoundsEnabled == true, "旧配置默认开启模式音效")
        expect(config?.keyLayers.contains(where: { $0.isDefault }) == true, "旧配置补齐默认层")
        expect(config?.shareVoiceToBlackHole == true, "旧配置默认开启语音共享")
        expect(config?.logTranscripts == false, "旧配置不把识别文本写入日志")
        expect(AppConfig().logTranscripts == false, "新配置默认不记录识别文本")
    }

    private static func testModelURLs() {
        let urls = ModelManager.baseURLs(repository: "a/b", mirror: "https://hf-mirror.com")
        expect(urls.count == 2, "主站 + 镜像 两个下载源")
        expect(urls[0].host == "huggingface.co", "首选 HuggingFace")
        expect(urls[1].host == "hf-mirror.com", "镜像地址正确")
    }

    private static func testTextCleanup() {
        expect(AppServices.cleanText("<|zh|><|NEUTRAL|><|Speech|>你好  世界") == "你好 世界", "清除 SenseVoice 标签")
        expect(AppServices.cleanText("  hello  ") == "hello", "去首尾空白")
    }

    private static func testWebRemotePage() {
        expect(WebPage.html.contains("getUserMedia"), "Web 遥控器页面包含麦克风采集")
        expect(WebPage.html.contains("/ws?token="), "Web 遥控器页面连接带 token 的 WebSocket")
        expect(WebPage.html.contains("data-key=\"ok\""), "Web 遥控器页面包含 OK 按键")
        var config = AppConfig()
        config.webRemoteEnabled = true
        config.webRemotePort = 50123
        let data = try! JSONEncoder().encode(config)
        let decoded = try! JSONDecoder().decode(AppConfig.self, from: data)
        expect(decoded.webRemoteEnabled && decoded.webRemotePort == 50123, "Web 遥控器配置可持久化")
    }

    private static func testWavReader() {
        let samples: [Int16] = [0, 1000, -1000, 32767]
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + samples.count * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(16000))
        append(UInt32(32000))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(samples.count * 2))
        for sample in samples { append(sample) }

        guard let wave = WavReader.parse(data: data) else {
            expect(false, "WAV 解析成功")
            return
        }
        expect(wave.sampleRate == 16000, "WAV 采样率解析")
        expect(wave.samples.count == samples.count, "WAV 样本数解析")
        expect(abs(wave.samples[1] - 1000.0 / 32768.0) < 0.0001, "WAV 样本值解析")
    }

    // MARK: - 工具

    private static func expect(_ condition: Bool, _ description: String) {
        checks += 1
        if !condition {
            failures += 1
            print("  ✗ \(description)")
        }
    }
}
