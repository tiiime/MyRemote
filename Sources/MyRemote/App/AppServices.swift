import Foundation
import AppKit
import IOKit.hid

extension Notification.Name {
    static let myRemoteStateChanged = Notification.Name("MyRemoteStateChanged")
}

/// 应用服务容器：把 HID / ATVV / 语音识别 / 分发 / 媒体控制串起来。
final class AppServices: NSObject, VoiceBridgeDelegate {

    static let shared = AppServices()

    // MARK: 状态快照（UI 只读）

    struct Snapshot {
        var atvvConnected = false
        var deviceName = ""
        var battery: Int?
        var tapOK = false
        var mappingOK = false
        var modelReady = false
        var modelDownloading = false
        var modelProgress: Double = 0
        var modelMessage = ""
        var capturing = false
        var transcribing = false
        /// 录音期间的准实时识别预览（仅命令/文字输入模式）。
        var partialTranscript: String?
        var lastTranscript: String?
        var lastError: String?
        /// 局域网 Web 遥控器状态。
        var webRemoteRunning = false
        var webRemoteURL = ""
        var webRemoteCA = ""
        var webRemoteError = ""
        /// 当前工作模式：默认转发 / 命令 / 输入。
        var voiceMode: VoiceMode = .forward
        /// 手动激活的映射层（nil = 跟随默认/应用层）。
        var manualLayerID: String?
        /// 当前前台应用 Bundle ID（用于应用层激活）。
        var frontmostAppBundleID: String?

        /// 兼容旧 UI 的只读判断。
        var actionMode: Bool { voiceMode == .command }
        /// 最近一次成功执行的指令名。
        var lastCommand: String?
        /// BlackHole 驱动是否安装。
        var blackHoleInstalled = false
        /// BlackHole 输出设备当前是否在线。
        var blackHoleDeviceOnline = false
    }

    private(set) var snapshot = Snapshot()

    private(set) var config = AppConfig()
    private let asr = SenseVoiceEngine()
    private let capture = VoiceCapture()
    private let asrQueue = DispatchQueue(label: "com.myremote.asrwork", qos: .userInitiated)

    private var atvv: ATVVBridge?
    private var hid: HIDEngine?
    private var tap: TapEngine?
    private let keyRouter = KeyRouter()
    private var modelManager: ModelManager
    private var decoder = ADPCMDecoder()
    private var enginesStarted = false

    private var blackHole: BlackHoleBridge?
    private let sharingLock = NSLock()
    private var sharingEnabled = false
    /// 本次语音会话是否真的在向虚拟声卡写数据（只在 ATVV 串行队列读写）。
    private var sharingThisSession = false
    /// 手动激活的映射层。
    private var manualLayerID: String?
    /// 前台应用（层激活条件）。
    private var frontmostAppBundleID: String?
    private var workspaceObserver: NSObjectProtocol?
    /// 音频线程读取当前模式（命令/文字输入模式不转发）。
    private let audioModeLock = NSLock()
    private var audioMode: VoiceMode = .forward

    // 局域网 Web 遥控器。
    private let webRemote = WebRemoteServer()
    private var webVoiceActive = false
    private var webVoiceMode: VoiceMode = .forward
    private var webVoiceSamples: [Int16] = []
    private var webVoiceBridge: BlackHoleBridge?
    private var webVoiceGeneration = 0

    // 录音期间的准实时识别预览。
    private var previewTimer: Timer?
    private var previewInFlight = false
    private var previewGeneration = 0
    private var previewMode: VoiceMode = .forward
    private var lastPreviewSampleCount = 0

    /// AppDelegate 注入：打开设置窗口。
    var showSettingsHandler: (() -> Void)?

    var modelDirectory: URL { ConfigStore.modelDirectory }

    override private init() {
        modelManager = ModelManager(repository: AppConfig().modelRepo,
                                    mirror: AppConfig().hfMirror,
                                    directory: ConfigStore.modelDirectory)
        super.init()
    }

    // MARK: - 生命周期

    /// 旧版 MiRemote 的 bundle id：它和本应用会争抢同一只遥控器，必须互斥。
    static let legacyBundleID = "com.miremote.controller"

    private func runningLegacyApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.legacyBundleID).first
    }

    func start() {
        config = ConfigStore.load()
        modelManager = ModelManager(repository: config.modelRepo, mirror: config.hfMirror,
                                    directory: ConfigStore.modelDirectory)
        configureVoiceSharing()
        _ = ModeSounds.shared
        startWorkspaceObserver()

        capture.onStart = { [weak self] in
            guard let self else { return }
            self.snapshot.capturing = true
            self.snapshot.partialTranscript = nil
            self.snapshot.lastError = nil
            self.startLivePreview()
            self.notify()
            if self.config.showToast { Toast.shared.show("🎤 聆听中…", duration: 30) }
        }
        capture.onFinish = { [weak self] samples in
            self?.handleVoiceFinished(samples)
        }

        if modelManager.isInstalled {
            loadModel()
        } else {
            Log.info("模型未安装，开始后台下载")
            downloadModel()
        }

        setupWorkspaceObservers()
        configureWebRemote()
        if config.webRemoteEnabled { startWebRemote() }

        if handleForeignRemoteApp() {
            startEngines()
        } else {
            snapshot.lastError = "检测到 MiRemote 正在运行：请先退出它，再点菜单「重新连接遥控器」"
        }

        if let missing = Permissions.firstMissing {
            Log.warn("权限未齐：辅助功能=\(Permissions.accessibility) 输入监控=\(Permissions.inputMonitoring)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let kind = Permissions.firstMissing {
                    PermissionGuideController.shared.show(kind)
                }
            }
        } else {
            Log.info("辅助功能与输入监控已授权")
        }
        notify()
    }

    private func startEngines() {
        guard !enginesStarted else { return }
        enginesStarted = true
        snapshot.lastError = nil
        keyRouter.onMode = { [weak self] mode in
            self?.setVoiceMode(mode)
        }
        keyRouter.onLayerAction = { [weak self] id in
            self?.setManualLayer(id)
        }
        keyRouter.onCommand = { [weak self] action in
            self?.executeKeyCommand(action)
        }
        keyRouter.resolveAction = { [weak self] key in
            self?.resolvedKeyAction(for: key)
        }

        tap = TapEngine()
        tap?.onKeyDown = { [weak self] key, isRepeat in
            self?.keyRouter.handle(key, isRepeat: isRepeat)
        }
        tap?.onHealth = { [weak self] tapOK, mappingOK in
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshot.tapOK = tapOK
                self.snapshot.mappingOK = mappingOK
                self.notify()
            }
        }
        tap?.start()

        hid = HIDEngine()
        hid?.onBackKey = { [weak self] isRepeat in
            self?.keyRouter.handle(.back, isRepeat: isRepeat)
        }
        hid?.onDeviceMatched = { [weak self] in
            self?.tap?.reinstallMapping()
        }
        hid?.start()

        atvv = ATVVBridge(delegate: self)
        atvv?.onBatteryLevel = { [weak self] percent in
            DispatchQueue.main.async {
                self?.snapshot.battery = percent
                self?.notify()
            }
        }
        atvv?.start()
    }

    private func stopEngines() {
        guard enginesStarted else { return }
        enginesStarted = false
        atvv?.stopAndWait()
        atvv = nil
        tap?.stop()
        tap = nil
        hid?.stop()
        hid = nil
        snapshot.atvvConnected = false
        snapshot.tapOK = false
        snapshot.mappingOK = false
        snapshot.voiceMode = .forward
    }

    func stop() {
        stopLivePreview()
        stopWebRemote()
        stopEngines()
        capture.cancel()
        asr.unload()
        blackHole?.stopNow()
        blackHole = nil
        sharingEnabled = false
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    /// 菜单「重新连接遥控器」：权限变更/蓝牙重启后无需重启 App。
    func restartRemoteConnection() {
        if runningLegacyApp() != nil {
            Toast.shared.show("MiRemote 仍在运行，请先退出它", duration: 2.5)
            return
        }
        stopEngines()
        startEngines()
        Toast.shared.show("正在重新连接遥控器…", duration: 1.2)
    }

    // MARK: - 与旧版 MiRemote 共存

    /// 启动时若发现旧版 MiRemote 在跑：提示互斥，可选择让本应用接管。
    private func handleForeignRemoteApp() -> Bool {
        guard let legacy = runningLegacyApp() else { return true }

        let alert = NSAlert()
        alert.messageText = "检测到旧版 MiRemote 正在运行"
        alert.informativeText = "两个应用会争抢同一只遥控器的按键与语音通道。建议先退出 MiRemote，再让 MyRemote 接管。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出 MiRemote 并继续")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        legacy.terminate()
        let deadline = Date().addingTimeInterval(5)
        while !legacy.isTerminated && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        guard legacy.isTerminated else {
            Toast.shared.show("MiRemote 没能退出，已跳过按键/语音接管", duration: 3)
            return false
        }
        Thread.sleep(forTimeInterval: 0.4)   // 等 MiRemote 恢复自己的 hidutil 映射
        return true
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.legacyBundleID else { return }
            Toast.shared.show("MiRemote 已启动，两者会冲突；建议退出其中一个", duration: 3)
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.legacyBundleID else { return }
            guard let self else { return }
            Toast.shared.show("MiRemote 已退出，重新接管遥控器…", duration: 1.5)
            self.restartRemoteConnection()
        }
    }

    // MARK: - 设置操作

    func showSettings() {
        showSettingsHandler?()
    }

    func updateConfig(_ mutate: (inout AppConfig) -> Void) {
        var next = config
        mutate(&next)
        let languageChanged = next.language != config.language || next.useItn != config.useItn
        let sharingChanged = next.shareVoiceToBlackHole != config.shareVoiceToBlackHole
            || next.blackHoleDeviceName != config.blackHoleDeviceName
        config = next
        ConfigStore.save(config)
        if let manualLayerID, !config.keyLayers.contains(where: { $0.id == manualLayerID }) {
            self.manualLayerID = nil
            snapshot.manualLayerID = nil
        }
        if languageChanged && asr.isReady {
            loadModel()
        }
        if sharingChanged {
            configureVoiceSharing()
        _ = ModeSounds.shared
        startWorkspaceObserver()
        } else {
            refreshAudioStatus()
        }
        notify()
    }

    func setLanguage(_ language: String) {
        updateConfig { $0.language = language }
        if config.showToast {
            Toast.shared.show(localized("识别语言：%@", Self.languageLabel(language)), duration: 1.2)
        }
    }

    static func languageLabel(_ code: String) -> String {
        switch code {
        case "zh": return localized("中文")
        case "en": return "English"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "yue": return localized("粤语")
        default: return localized("自动")
        }
    }

    /// 写进日志的识别文本：默认只留字数，避免把用户说的话明文落盘。
    private func loggedText(_ text: String) -> String {
        config.logTranscripts ? text : "已省略 \(text.count) 字（默认不记录识别文本）"
    }

    func copyLastTranscript() {
        guard let text = snapshot.lastTranscript, !text.isEmpty else {
            Toast.shared.show("还没有识别记录")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.shared.show(localized("已复制：%@", text))
    }

    // MARK: - 模型

    private func loadModel() {
        let modelPath = modelManager.modelURL.path
        let tokensPath = modelManager.tokensURL.path
        let language = config.language
        let useItn = config.useItn
        guard FileManager.default.fileExists(atPath: modelPath) else {
            snapshot.modelReady = false
            notify()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.asr.load(modelPath: modelPath, tokensPath: tokensPath,
                                  language: language, useItn: useItn)
                DispatchQueue.main.async {
                    self.snapshot.modelReady = true
                    self.snapshot.modelMessage = "模型已就绪"
                    self.notify()
                }
                Log.info("SenseVoice 模型加载完成（language=\(language), itn=\(useItn)）")
            } catch {
                DispatchQueue.main.async {
                    self.snapshot.modelReady = false
                    self.snapshot.lastError = error.localizedDescription
                    self.snapshot.modelMessage = "模型加载失败：\(error.localizedDescription)"
                    self.notify()
                }
                Log.error("模型加载失败: \(error)")
            }
        }
    }

    func downloadModel() {
        guard !modelManager.isDownloading else { return }
        snapshot.modelDownloading = true
        snapshot.modelProgress = 0
        snapshot.modelMessage = "准备下载…"
        notify()

        modelManager.install(progress: { [weak self] fraction, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshot.modelProgress = fraction
                self.snapshot.modelMessage = message
                self.notify()
            }
        }, completion: { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.snapshot.modelDownloading = false
                switch result {
                case .success:
                    self.snapshot.modelMessage = "下载完成，正在加载…"
                    self.notify()
                    self.loadModel()
                    if self.config.showToast { Toast.shared.show("语音模型下载完成", duration: 2) }
                case .failure(let error):
                    self.snapshot.modelMessage = error.localizedDescription
                    self.snapshot.lastError = error.localizedDescription
                    self.notify()
                    if self.config.showToast { Toast.shared.show(error.localizedDescription, duration: 4) }
                }
            }
        })
    }

    // MARK: - 语音链路（ATVV delegate，BLE 队列）

    func atvvConnected(name: String) {
        DispatchQueue.main.async {
            self.snapshot.atvvConnected = true
            self.snapshot.deviceName = name
            self.notify()
        }
    }

    func atvvDisconnected(reason: String?) {
        DispatchQueue.main.async {
            self.snapshot.atvvConnected = false
            self.snapshot.deviceName = ""
            self.capture.cancel()
            self.snapshot.capturing = false
            if let reason, !reason.isEmpty {
                Log.warn("ATVV 断开: \(reason)")
                if reason.contains("unauthorized") {
                    self.snapshot.lastError = "蓝牙未授权：系统设置 → 隐私与安全性 → 蓝牙 中允许 MyRemote，然后重新连接"
                    if self.config.showToast {
                        Toast.shared.show("蓝牙未授权，语音不可用（去系统设置允许后点菜单「重新连接遥控器」）",
                                          duration: 3.5)
                    }
                }
            }
            self.notify()
        }
    }

    func atvvVoiceStarted() {
        decoder = ADPCMDecoder()
        capture.start()
        sharingThisSession = false
        // 只有音频输入模式才把音频转发给其他 App；命令/文字输入模式只做本地识别。
        guard currentAudioMode().forwardsAudioToOtherApps else { return }
        if let bridge = sharingBridge(), bridge.isDeviceAvailable {
            bridge.streamStarted(sampleRate: 16000)
            sharingThisSession = true
        } else if sharingBridge() != nil {
            Log.warn("语音共享已开启，但 BlackHole 设备不在线")
        }
    }

    func atvvAudioFrame(_ frame: Data, sync: (predictor: Int16, stepIndex: Int)?) {
        if let sync { decoder.reset(predictor: sync.predictor, stepIndex: sync.stepIndex) }
        let pcm = decoder.decode(frame)
        capture.append(pcm)
        if sharingThisSession, currentAudioMode().forwardsAudioToOtherApps,
           let bridge = sharingBridge() {
            bridge.write(pcm)
        }
    }

    func atvvVoiceStopped() {
        if sharingThisSession, let bridge = sharingBridge() {
            bridge.streamStopped()
        }
        sharingThisSession = false
        capture.stop()
    }

    // MARK: - 语音共享（BlackHole）

    private func currentAudioMode() -> VoiceMode {
        audioModeLock.lock()
        defer { audioModeLock.unlock() }
        return audioMode
    }

    private func sharingBridge() -> BlackHoleBridge? {
        sharingLock.lock()
        defer { sharingLock.unlock() }
        return sharingEnabled ? blackHole : nil
    }

    private func configureVoiceSharing() {
        sharingLock.lock()
        let previous = blackHole
        blackHole = nil
        sharingEnabled = false
        sharingLock.unlock()
        previous?.stopNow()

        if config.shareVoiceToBlackHole {
            let bridge = BlackHoleBridge(deviceNamePrefix: config.blackHoleDeviceName)
            sharingLock.lock()
            blackHole = bridge
            sharingEnabled = true
            sharingLock.unlock()
            if !bridge.isDeviceAvailable {
                Log.warn("BlackHole 设备不在线：安装驱动后需要重启音频服务")
            }
        }
        refreshAudioStatus()
    }

    /// 设置页手动刷新虚拟声卡状态。
    func refreshAudioStatusForUI() {
        refreshAudioStatus()
    }

    private func refreshAudioStatus() {
        let installed = AudioDevices.blackHoleInstalled
        let online = AudioDevices.findOutputDevice(namePrefix: config.blackHoleDeviceName) != nil
        if snapshot.blackHoleInstalled != installed || snapshot.blackHoleDeviceOnline != online {
            snapshot.blackHoleInstalled = installed
            snapshot.blackHoleDeviceOnline = online
            notify()
        }
    }

    // MARK: - 准实时预览

    private func startLivePreview() {
        stopLivePreview()
        previewMode = snapshot.voiceMode
        previewGeneration += 1
        lastPreviewSampleCount = 0
        guard previewMode != .forward else { return }

        let timer = Timer(timeInterval: 0.9, repeats: true) { [weak self] _ in
            self?.runLivePreview()
        }
        RunLoop.main.add(timer, forMode: .common)
        previewTimer = timer
    }

    private func stopLivePreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewGeneration += 1
        previewInFlight = false
        lastPreviewSampleCount = 0
    }

    private func runLivePreview() {
        let samples = capture.sampleSnapshot()
        guard previewMode != .forward,
              snapshot.voiceMode == previewMode,
              !previewInFlight,
              asr.isReady,
              samples.count >= 8_000,
              samples.count >= lastPreviewSampleCount + 4_800 else {
            return
        }
        lastPreviewSampleCount = samples.count
        previewInFlight = true
        let generation = previewGeneration

        asrQueue.async { [weak self] in
            guard let self else { return }
            let audio = self.trimSilence(samples)
            guard audio.count >= 4_000 else {
                DispatchQueue.main.async { self.previewInFlight = false }
                return
            }
            do {
                let transcript = try self.asr.transcribe(
                    samples: audio.map { Float($0) / 32768.0 }
                )
                let text = Self.cleanText(transcript.text)
                DispatchQueue.main.async {
                    self.previewInFlight = false
                    guard generation == self.previewGeneration,
                          self.snapshot.capturing,
                          self.previewMode != .forward,
                          self.previewMode == self.snapshot.voiceMode else { return }
                    self.snapshot.partialTranscript = text
                    self.notify()
                    if self.config.showToast, !text.isEmpty {
                        Toast.shared.show("🎤 聆听中… \(text)", duration: 1.4)
                    }
                }
            } catch {
                DispatchQueue.main.async { self.previewInFlight = false }
            }
        }
    }

    // MARK: - 局域网 Web 遥控器

    private func configureWebRemote() {
        webRemote.onState = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshot.webRemoteRunning = state.phase == .running
                self.snapshot.webRemoteURL = state.url
                self.snapshot.webRemoteCA = state.caPath
                self.snapshot.webRemoteError = state.error
                self.notify()
            }
        }
        webRemote.onKey = { [weak self] key in
            DispatchQueue.main.async { self?.keyRouter.handle(key, isRepeat: false) }
        }
        webRemote.onMode = { [weak self] mode in
            DispatchQueue.main.async { self?.setVoiceMode(mode) }
        }
        webRemote.onVoiceStart = { [weak self] mode in
            guard let self else { return false }
            if Thread.isMainThread { return self.beginWebVoice(mode) }
            var ok = false
            DispatchQueue.main.sync { ok = self.beginWebVoice(mode) }
            return ok
        }
        webRemote.onVoiceData = { [weak self] data in
            DispatchQueue.main.async { self?.appendWebVoice(data) }
        }
        webRemote.onVoiceStop = { [weak self] in
            DispatchQueue.main.async { self?.endWebVoice() }
        }
        webRemote.currentMode = { [weak self] in self?.snapshot.voiceMode ?? .forward }
    }

    func setWebRemoteEnabled(_ enabled: Bool) {
        updateConfig { $0.webRemoteEnabled = enabled }
        if enabled { startWebRemote() } else { stopWebRemote() }
    }

    func startWebRemote() {
        let raw = config.webRemotePort
        let port = raw > 0 && raw <= 65535 ? UInt16(raw) : 47823
        webRemote.start(port: port)
    }

    func stopWebRemote() {
        webRemote.stop()
        cancelWebVoice()
        snapshot.webRemoteRunning = false
        snapshot.webRemoteURL = ""
        snapshot.webRemoteError = ""
        notify()
    }

    private func beginWebVoice(_ mode: VoiceMode) -> Bool {
        guard !webVoiceActive, !capture.isActive else { return false }

        if mode == .forward {
            guard let bridge = sharingBridge(), bridge.isDeviceAvailable else {
                Log.warn("Web 遥控器：BlackHole 不可用，无法转发手机麦克风")
                return false
            }
            bridge.streamStarted(sampleRate: 16000)
            webVoiceBridge = bridge
        } else {
            guard asr.isReady else { return false }
        }

        webVoiceGeneration += 1
        webVoiceMode = mode
        webVoiceSamples.removeAll(keepingCapacity: true)
        webVoiceActive = true
        setVoiceMode(mode)
        snapshot.capturing = true
        snapshot.transcribing = false
        notify()
        return true
    }

    private func appendWebVoice(_ data: Data) {
        guard webVoiceActive, data.count >= 2 else { return }
        let bytes = [UInt8](data)
        var samples = [Int16](repeating: 0, count: bytes.count / 2)
        for index in 0..<samples.count {
            let low = UInt16(bytes[index * 2])
            let high = UInt16(bytes[index * 2 + 1]) << 8
            samples[index] = Int16(bitPattern: low | high)
        }

        if webVoiceMode == .forward {
            webVoiceBridge?.write(samples)
        } else if webVoiceSamples.count < 16000 * 90 {
            webVoiceSamples.append(contentsOf: samples)
        }
    }

    private func endWebVoice() {
        guard webVoiceActive else { return }
        webVoiceActive = false
        let mode = webVoiceMode
        webVoiceBridge?.streamStopped()
        webVoiceBridge = nil
        snapshot.capturing = false
        notify()

        if mode == .forward {
            if config.showToast { Toast.shared.show("手机语音已转发到 BlackHole", duration: 1.6) }
            return
        }

        let samples = webVoiceSamples
        webVoiceSamples.removeAll(keepingCapacity: true)
        let generation = webVoiceGeneration
        guard asr.isReady else {
            Toast.shared.show("语音模型还没准备好", duration: 2)
            return
        }

        snapshot.transcribing = true
        notify()
        asrQueue.async { [weak self] in
            guard let self else { return }
            do {
                let audio = self.trimSilence(samples)
                guard audio.count >= 4_000 else {
                    DispatchQueue.main.async {
                        self.snapshot.transcribing = false
                        self.notify()
                        Toast.shared.show("没听清，再说一次？", duration: 1.5)
                    }
                    return
                }
                let transcript = try self.asr.transcribe(samples: audio.map { Float($0) / 32768.0 })
                let text = Self.cleanText(transcript.text)
                DispatchQueue.main.async {
                    guard generation == self.webVoiceGeneration else { return }
                    self.snapshot.transcribing = false
                    self.snapshot.lastTranscript = text
                    self.notify()
                    self.webRemote.sendTranscript(text)
                    let meaningful = text.contains { $0.isLetter || $0.isNumber }
                    guard !text.isEmpty, meaningful else {
                        if self.config.showToast { Toast.shared.show("没识别到文字", duration: 1.5) }
                        return
                    }
                    if mode == .command {
                        self.runCommand(text)
                    } else {
                        self.deliver(text)
                    }
                }
                Log.info("Web 语音识别完成（\(String(format: "%.2f", transcript.duration))s）")
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.webVoiceGeneration else { return }
                    self.snapshot.transcribing = false
                    self.notify()
                    self.webRemote.sendError(error.localizedDescription)
                    Toast.shared.show("识别失败：\(error.localizedDescription)", duration: 3)
                }
            }
        }
    }

    private func cancelWebVoice() {
        webVoiceGeneration += 1
        if webVoiceActive {
            webVoiceActive = false
            webVoiceBridge?.streamStopped()
            webVoiceBridge = nil
            webVoiceSamples.removeAll(keepingCapacity: true)
            snapshot.capturing = false
            snapshot.transcribing = false
            notify()
        }
    }

    // MARK: - 识别与分发

    private func handleVoiceFinished(_ samples: [Int16]) {
        stopLivePreview()
        snapshot.capturing = false
        snapshot.partialTranscript = nil
        notify()

        // 音频输入模式：只转发音频，不做识别、不输入文字。
        if snapshot.voiceMode == .forward {
            if config.showToast {
                let forwarded = config.shareVoiceToBlackHole && snapshot.blackHoleDeviceOnline
                Toast.shared.show(forwarded ? "语音已转发到 BlackHole" : "音频输入模式：语音共享未就绪",
                                  duration: 1.5)
            }
            return
        }

        let audio = trimSilence(samples)
        guard audio.count > 3200 else {   // < 200ms 视为没说话
            if config.showToast { Toast.shared.show("没听清，再说一次？", duration: 1.5) }
            return
        }
        guard asr.isReady else {
            Toast.shared.show("语音模型还没准备好", duration: 2)
            return
        }

        snapshot.transcribing = true
        notify()

        asrQueue.async { [weak self] in
            guard let self else { return }
            let floats = audio.map { Float($0) / 32768.0 }
            do {
                let transcript = try self.asr.transcribe(samples: floats)
                let text = Self.cleanText(transcript.text)
                DispatchQueue.main.async {
                    self.snapshot.transcribing = false
                    self.snapshot.lastTranscript = text
                    self.notify()
                    let meaningful = text.contains { $0.isLetter || $0.isNumber }
                    guard !text.isEmpty, meaningful else {
                        if self.config.showToast { Toast.shared.show("没识别到文字", duration: 1.5) }
                        return
                    }
                    if self.snapshot.voiceMode == .command {
                        self.runCommand(text)
                    } else {
                        self.deliver(text)
                    }
                }
                Log.info("识别完成（\(String(format: "%.2f", transcript.duration))s, lang=\(transcript.language)）：\(loggedText(text))")
            } catch {
                DispatchQueue.main.async {
                    self.snapshot.transcribing = false
                    self.snapshot.lastError = error.localizedDescription
                    self.notify()
                    Toast.shared.show(localized("识别失败：%@", error.localizedDescription), duration: 3)
                }
                Log.error("识别失败: \(error)")
            }
        }
    }

    private func deliver(_ text: String) {
        let meaningful = text.contains(where: { $0.isLetter || $0.isNumber })
        guard !text.isEmpty, meaningful else {
            if config.showToast { Toast.shared.show("没识别到文字", duration: 1.5) }
            return
        }
        let result = TextInjector.deliver(text, autoPaste: config.autoPaste)
        switch result {
        case .pasted:
            if config.showToast {
                Toast.shared.show("🎤 聆听中… \(text)", duration: 2.4)
            }
        case .copied:
            if config.showToast {
                Toast.shared.show(config.autoPaste
                         ? "🎤 聆听中… \(text)\n已复制（缺少辅助功能权限）"
                         : "🎤 聆听中… \(text)\n已复制",
                                  duration: 2.4)
            }
        case .failed(let reason):
            Toast.shared.show("🎤 聆听中… \(text)\n投递失败：\(reason)", duration: 2.6)
        }
    }

    // MARK: - 工作模式

    func setVoiceMode(_ mode: VoiceMode) {
        guard snapshot.voiceMode != mode else { return }
        snapshot.voiceMode = mode
        audioModeLock.lock()
        audioMode = mode
        audioModeLock.unlock()
        if mode != .forward {
            // 命令/文字输入模式绝不向其他 App 转发音频。
            sharingBridge()?.stopNow()
        }
        notify()

        if config.modeSoundsEnabled {
            ModeSounds.shared.play(mode)
        }

        guard config.showToast else { return }
        // 切换提示只报模式名：不带示例，也不再复述各模式的行为。
        Toast.shared.show(mode.switchToastText, duration: 1.6)
    }

    // MARK: - 按键层

    private func startWorkspaceObserver() {
        frontmostAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        snapshot.frontmostAppBundleID = frontmostAppBundleID
        let center = NSWorkspace.shared.notificationCenter
        workspaceObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            guard id != self.frontmostAppBundleID else { return }
            self.frontmostAppBundleID = id
            self.snapshot.frontmostAppBundleID = id
            self.notify()
        }
    }

    /// 按键复用指令系统的执行能力（应用 / 网页 / Shell / DSH）。
    private func executeKeyCommand(_ action: CommandAction) {
        Log.info("按键指令：\(action.summary)")
        if config.showToast {
            Toast.shared.show(localized("执行：%@", action.summary), duration: 1.4)
        }
        CommandRunner.execute(action, input: "") { [weak self] ok, message in
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.snapshot.lastCommand = action.summary
                    self.notify()
                }
                if self.config.showToast {
                    Toast.shared.show((ok ? "✓ " : "✗ ") + message, duration: 2.2)
                }
            }
        }
    }

    private func resolvedKeyAction(for key: RemoteKey) -> KeyAction? {
        KeymapResolver.resolve(key: key, layers: config.keyLayers,
                               manualID: manualLayerID,
                               frontmostBundleID: frontmostAppBundleID)?.action
    }

    /// 手动激活层；传 nil 回到默认解析。
    func setManualLayer(_ id: String?) {
        guard let id else {
            manualLayerID = nil
            snapshot.manualLayerID = nil
            notify()
            if config.showToast { Toast.shared.show("已回到默认层", duration: 1.2) }
            return
        }
        guard config.keyLayers.contains(where: { $0.id == id && !$0.isDefault }) else {
            return
        }
        // 再次触发同一层 = 取消，便于用一个键来回切。
        if manualLayerID == id {
            manualLayerID = nil
            snapshot.manualLayerID = nil
            notify()
            if config.showToast { Toast.shared.show(localized("已取消层：%@", layerName(id)), duration: 1.4) }
            return
        }
        manualLayerID = id
        snapshot.manualLayerID = id
        notify()
        if config.showToast { Toast.shared.show(localized("已激活层：%@", layerName(id)), duration: 1.4) }
    }

    private func layerName(_ id: String) -> String {
        config.keyLayers.first(where: { $0.id == id })?.name ?? id
    }

    private func runCommand(_ text: String) {
        guard let rule = CommandMatcher.firstMatch(text, rules: config.commandRules) else {
            var message = "🎤 聆听中… \(text)\n没有匹配的指令"
            let hints = config.commandRules.filter(\.enabled).prefix(3).map(\.name)
            if !hints.isEmpty {
                message += "\n可用：\(hints.joined(separator: " / "))"
            }
            Toast.shared.show(message, duration: 3)
            return
        }

        Log.info("指令命中：\(rule.name) ← \(loggedText(text))")
        if config.showToast {
            Toast.shared.show("🎤 聆听中… \(text)\n⚡ \(rule.name)", duration: 2.4)
        }

        CommandRunner.execute(rule.action, input: text) { [weak self] ok, message in
            guard let self else { return }
            Log.info("指令执行\(ok ? "成功" : "失败")\(config.logTranscripts ? "：\(message)" : "")")
            if ok {
                self.snapshot.lastCommand = rule.name
                self.notify()
            }
            if self.config.showToast {
                Toast.shared.show("🎤 聆听中… \(text)\n" + (ok ? "✓ " : "✗ ") + message,
                                  duration: 2.6)
            }
        }
    }

    /// 去掉 SenseVoice 结果里的控制标签（如 <|zh|><|NEUTRAL|>）。
    static func cleanText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 去掉首尾静音，避免长静音触发模型幻觉。
    private func trimSilence(_ samples: [Int16]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        let threshold = 300
        var start = 0
        var end = samples.count
        while start < end && abs(Int(samples[start])) < threshold { start += 1 }
        while end > start && abs(Int(samples[end - 1])) < threshold { end -= 1 }
        guard start < end else { return [] }
        let margin = 1600
        start = max(0, start - margin)
        end = min(samples.count, end + margin)
        return Array(samples[start..<end])
    }

    // MARK: - 状态

    private func notify() {
        NotificationCenter.default.post(name: .myRemoteStateChanged, object: nil)
    }
}
