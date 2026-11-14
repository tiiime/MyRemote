import Foundation
import CoreGraphics

/// CGEventTap：捕获 hidutil 中转键（F13–F20 / 小键盘 Clear / Divide / Multiply），
/// 吞掉并回调逻辑键。需要「辅助功能」权限。
///
/// 失效安全：tap 被系统禁用时立即尝试重启；重启失败就卸载 hidutil 映射，
/// 绝不允许「映射在、过滤器不在」的中转键泄漏态；健康检查周期性重试恢复。
final class TapEngine {

    /// 中转键按下（含 autorepeat）。返回后事件被吞掉。
    var onKeyDown: ((RemoteKey, _ isRepeat: Bool) -> Void)?
    var onHealth: ((_ tapOK: Bool, _ mappingOK: Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: DispatchSourceTimer?
    private let healthQueue = DispatchQueue(label: "com.myremote.taphealth")
    private var running = false

    // MARK: - 生命周期

    func start() {
        healthQueue.sync {
            guard !running else { return }
            running = true
            startTapLocked()
            startHealthTimerLocked()
        }
    }

    func stop() {
        healthQueue.sync {
            running = false
            healthTimer?.cancel()
            healthTimer = nil
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            tap = nil
            runLoopSource = nil
            KeyRemapper.uninstall()
        }
    }

    /// 蓝牙重连 / 系统唤醒后重装映射（幂等）。
    func reinstallMapping() {
        healthQueue.async { [weak self] in
            guard let self, self.running, self.tap != nil else { return }
            _ = KeyRemapper.install()
            self.onHealth?(self.tap != nil, KeyRemapper.isInstalled())
        }
    }

    // MARK: - 内部

    private func startTapLocked() {
        guard let (newTap, source) = makeTap() else {
            Log.error("TAP 创建失败（需要辅助功能权限），卸载可能残留的 hidutil 映射")
            _ = KeyRemapper.uninstall()
            onHealth?(false, false)
            return
        }
        tap = newTap
        runLoopSource = source
        let mappingOK = KeyRemapper.install()
        onHealth?(true, mappingOK)
        Log.info(mappingOK ? "TAP 就绪，hidutil 中转映射已安装" : "TAP 就绪，但 hidutil 映射安装失败")
    }

    private func makeTap() -> (CFMachPort, CFRunLoopSource?)? {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)
                              | (1 << CGEventType.tapDisabledByTimeout.rawValue)
                              | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<TapEngine>.fromOpaque(userInfo).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            },
            userInfo: pointer) else { return nil }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return (tap, source)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 系统临时禁用：立即重开。重开失败由健康检查兜底。
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.warn("TAP 被系统禁用，已尝试重开")
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let key = KeyRemapper.keycodeMap[keycode] else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            onKeyDown?(key, isRepeat)
        }
        // 吞掉：中转键绝不允许进入前台应用。
        return nil
    }

    private func startHealthTimerLocked() {
        guard healthTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: healthQueue)
        timer.schedule(deadline: .now() + 20, repeating: 20)
        timer.setEventHandler { [weak self] in
            guard let self, self.running else { return }
            if self.tap == nil {
                // 启动时权限未授予导致 tap 创建失败：权限补上后自动重建。
                self.startTapLocked()
                self.onHealth?(self.tap != nil, KeyRemapper.isInstalled())
                return
            }
            if let tap = self.tap, !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                Log.warn("TAP 健康检查：发现被禁用，已重开")
            }
            let mappingOK = KeyRemapper.isInstalled()
            if self.tap != nil && !mappingOK {
                let ok = KeyRemapper.install()
                Log.warn("TAP 健康检查：映射缺失，重装\(ok ? "成功" : "失败")")
            }
            self.onHealth?(self.tap != nil, KeyRemapper.isInstalled())
        }
        timer.resume()
        healthTimer = timer
    }
}
