import Foundation
import IOKit.hid

/// IOHID 监听通道。
///
/// 只负责两件事：
/// 1. 读 `back`（usage 0xF1）——它超出标准键盘 usage 范围，hidutil 不能重映射，
///    系统也不会处理，只能走 IOHID 原始事件（与 MiRemote 实机验证一致）。
/// 2. 设备接入/移除通知——蓝牙重连后重装 hidutil 中转映射。
///
/// 其余按键由 TapEngine 处理（hidutil 中转 + CGEventTap）。
final class HIDEngine {

    var onBackKey: ((_ isRepeat: Bool) -> Void)?
    var onDeviceMatched: (() -> Void)?
    var onDeviceRemoved: (() -> Void)?

    private static let vendorID = KeyRemapper.vendorID
    private static let productID = KeyRemapper.productID
    private static let keyboardUsagePage: UInt32 = 0x07
    private static let noiseUsage: UInt32 = 0xFFFFFFFF
    private static let backUsage: UInt32 = 0xF1

    private var manager: IOHIDManager?
    private var backDown = false

    func start() {
        guard manager == nil else { return }

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, HIDEngine.inputValueCallback, context)
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, HIDEngine.deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, HIDEngine.deviceRemovedCallback, context)
        // .commonModes：GUI 事件追踪等非 default 模式下也保持回调不断流。
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            Log.info("HID: 监听通道已打开")
        } else {
            Log.error(String(format: "HID: 打开失败 0x%08X（需要「输入监控」权限）", result))
        }
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        backDown = false
    }

    // MARK: - 回调

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == Self.keyboardUsagePage else { return }
        let usage = IOHIDElementGetUsage(element)
        guard usage != Self.noiseUsage else { return }

        let isDown = IOHIDValueGetIntegerValue(value) != 0
        guard usage == Self.backUsage else { return }

        if isDown {
            let isRepeat = backDown
            backDown = true
            onBackKey?(isRepeat)
        } else {
            backDown = false
        }
    }

    private func handleDeviceMatched() {
        Log.info("HID: 遥控器接入")
        onDeviceMatched?()
    }

    private func handleDeviceRemoved() {
        Log.warn("HID: 遥控器移除")
        onDeviceRemoved?()
    }

    // MARK: - C 回调蹦床

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        Unmanaged<HIDEngine>.fromOpaque(context).takeUnretainedValue().handleInputValue(value)
    }

    private static let deviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<HIDEngine>.fromOpaque(context).takeUnretainedValue().handleDeviceMatched()
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<HIDEngine>.fromOpaque(context).takeUnretainedValue().handleDeviceRemoved()
    }
}
