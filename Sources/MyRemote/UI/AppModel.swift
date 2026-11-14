import Foundation
import SwiftUI
import AppKit

/// 设置窗口的 ViewModel：订阅 AppServices 状态并转发操作。
final class SettingsModel: ObservableObject {

    @Published var snapshot: AppServices.Snapshot
    @Published var config: AppConfig

    let services: AppServices

    init(services: AppServices) {
        self.services = services
        self.snapshot = services.snapshot
        self.config = services.config
        NotificationCenter.default.addObserver(forName: .myRemoteStateChanged, object: nil,
                                               queue: .main) { [weak self] _ in
            guard let self else { return }
            self.snapshot = self.services.snapshot
            self.config = self.services.config
        }
    }

    // MARK: - 语音

    func setLanguage(_ code: String) {
        services.updateConfig { $0.language = code }
        config = services.config
    }

    func setAutoPaste(_ value: Bool) {
        services.updateConfig { $0.autoPaste = value }
        config = services.config
    }

    func setToast(_ value: Bool) {
        services.updateConfig { $0.showToast = value }
        config = services.config
    }

    func setShareVoice(_ value: Bool) {
        services.updateConfig { $0.shareVoiceToBlackHole = value }
        config = services.config
    }

    func refreshAudioStatus() {
        services.refreshAudioStatusForUI()
    }

    func setLogTranscripts(_ value: Bool) {
        services.updateConfig { $0.logTranscripts = value }
        config = services.config
    }

    func setModeSounds(_ value: Bool) {
        services.updateConfig { $0.modeSoundsEnabled = value }
        config = services.config
    }

    func previewModeSound() {
        ModeSounds.shared.play(snapshot.voiceMode)
    }

    func downloadModel() {
        services.downloadModel()
    }

    // MARK: - 指令


    func setVoiceMode(_ mode: VoiceMode) {
        services.setVoiceMode(mode)
    }

    func setCommandEnabled(id: String, enabled: Bool) {
        services.updateConfig { config in
            if let index = config.commandRules.firstIndex(where: { $0.id == id }) {
                config.commandRules[index].enabled = enabled
            }
        }
        self.config = services.config
    }

    func upsertCommand(_ rule: CommandRule) {
        services.updateConfig { config in
            if let index = config.commandRules.firstIndex(where: { $0.id == rule.id }) {
                config.commandRules[index] = rule
            } else {
                config.commandRules.append(rule)
            }
        }
        self.config = services.config
    }

    func deleteCommand(id: String) {
        services.updateConfig { $0.commandRules.removeAll { $0.id == id } }
        self.config = services.config
    }

    func moveCommand(id: String, offset: Int) {
        services.updateConfig { config in
            guard let index = config.commandRules.firstIndex(where: { $0.id == id }) else { return }
            let target = index + offset
            guard config.commandRules.indices.contains(target) else { return }
            config.commandRules.swapAt(index, target)
        }
        self.config = services.config
    }

    // MARK: - 按键层

    func upsertKeyLayer(_ layer: KeyLayer) {
        services.updateConfig { config in
            if let index = config.keyLayers.firstIndex(where: { $0.id == layer.id }) {
                config.keyLayers[index] = layer
            } else {
                config.keyLayers.append(layer)
            }
        }
        config = services.config
    }

    func deleteKeyLayer(id: String) {
        guard id != KeyLayer.defaultID else { return }
        services.updateConfig { config in
            config.keyLayers.removeAll { $0.id == id }
        }
        if snapshot.manualLayerID == id {
            services.setManualLayer(nil)
        }
        config = services.config
    }

    func setKeyBinding(layerID: String, key: RemoteKey, actionID: String?) {
        services.updateConfig { config in
            guard let index = config.keyLayers.firstIndex(where: { $0.id == layerID }) else { return }
            if let actionID {
                config.keyLayers[index].bindings[key.rawValue] = actionID
            } else {
                config.keyLayers[index].bindings.removeValue(forKey: key.rawValue)
            }
        }
        config = services.config
    }

    func setManualLayer(_ id: String?) {
        services.setManualLayer(id)
    }

    // MARK: - 环境

    func restartRemote() {
        services.restartRemoteConnection()
    }

    var legacyMiRemoteRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppServices.legacyBundleID)
            .first != nil
    }

    func refreshPermissions() {
        objectWillChange.send()
    }
}
