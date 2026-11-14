import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    MyRemote — 小米蓝牙遥控器 2 Pro 的 macOS 媒体遥控 + 本地语音输入

    用法:
      MyRemote                启动菜单栏应用
      MyRemote --self-test    运行内置自检
      MyRemote --web-test     只启动 Web 遥控器（开发调试）
      MyRemote --asr <wav>    用本地 SenseVoice 模型转写一段 WAV
      MyRemote --list-dsh     列出本机 DSH 会话
      MyRemote --send-dsh <标题> <消息> [--execute]
                              向 DSH 会话发送消息（默认只解析目标）

    环境变量:
      MYREMOTE_MODEL_DIR      指定模型目录（默认 ~/Library/Application Support/MyRemote/Models/sensevoice）
    """)
    exit(0)
}

if let index = arguments.firstIndex(of: "--render-key-shortcut-editor"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderKeyShortcutEditor(to: arguments[index + 1]) ? 0 : 13)
}

if let index = arguments.firstIndex(of: "--render-key-command-editor"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderKeyCommandEditor(to: arguments[index + 1]) ? 0 : 12)
}

if let index = arguments.firstIndex(of: "--render-keymap"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderKeymap(to: arguments[index + 1]) ? 0 : 11)
}

if let index = arguments.firstIndex(of: "--render-status-icons"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderStatusIcons(to: arguments[index + 1]) ? 0 : 10)
}

if let index = arguments.firstIndex(of: "--render-status-panel"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderStatusPanel(to: arguments[index + 1]) ? 0 : 9)
}

if let index = arguments.firstIndex(of: "--render-permission-guide"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderPermissionGuide(to: arguments[index + 1]) ? 0 : 5)
}

if let index = arguments.firstIndex(of: "--render-rule-editor"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderRuleEditor(to: arguments[index + 1]) ? 0 : 5)
}

if let index = arguments.firstIndex(of: "--render-ui"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderUI(to: arguments[index + 1]) ? 0 : 5)
}

if let index = arguments.firstIndex(of: "--render-settings"), index + 1 < arguments.count {
    exit(SettingsRenderer.renderDashboard(to: arguments[index + 1]) ? 0 : 5)
}

if arguments.contains("--list-dsh") {
    exit(DSHRunner.list() ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--send-dsh"), index + 2 < arguments.count {
    exit(DSHRunner.send(title: arguments[index + 1], message: arguments[index + 2],
                        execute: arguments.contains("--execute")) ? 0 : 2)
}

if let index = arguments.firstIndex(of: "--send-dsh-id"), index + 2 < arguments.count {
    exit(DSHRunner.send(sessionId: arguments[index + 1], message: arguments[index + 2],
                        execute: arguments.contains("--execute")) ? 0 : 2)
}

if let index = arguments.firstIndex(of: "--test-command"), index + 1 < arguments.count {
    exit(CommandRunnerCLI.run(text: arguments[index + 1],
                              execute: arguments.contains("--execute")) ? 0 : 6)
}

if let index = arguments.firstIndex(of: "--export-mode-sounds"), index + 1 < arguments.count {
    exit(ModeSounds.export(to: arguments[index + 1]) ? 0 : 8)
}

if arguments.contains("--test-blackhole") {
    exit(AudioRunner.testBlackHole() ? 0 : 7)
}

if arguments.contains("--download-selftest") {
    exit(DownloadRunner.runChunkedSelfTest() ? 0 : 4)
}

if arguments.contains("--download-model") {
    exit(DownloadRunner.run() ? 0 : 3)
}

if arguments.contains("--web-test") {
    WebRunner.run()
}

if arguments.contains("--self-test") {
    exit(SelfTest.run() ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--asr"), index + 1 < arguments.count {
    exit(ASRRunner.run(wavPath: arguments[index + 1]) ? 0 : 2)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
