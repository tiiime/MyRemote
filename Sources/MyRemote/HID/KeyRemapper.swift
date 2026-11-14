import Foundation
import CoreGraphics
import os

/// 小米蓝牙遥控器 2 Pro 的 13 个实体键（键盘页 usage，实机探针确认）。
/// 移植自 MiRemote（MIT）。
enum RemoteKey: String, CaseIterable, Codable {
    case power, voice, up, down, left, right, ok, back, home, menu, tv, volUp, volDown

    var displayName: String {
        switch self {
        case .power: return "电源"
        case .voice: return "语音"
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        case .ok: return "OK"
        case .back: return "返回"
        case .home: return "主页"
        case .menu: return "菜单"
        case .tv: return "TV"
        case .volUp: return "音量+"
        case .volDown: return "音量-"
        }
    }

    static let usageMap: [UInt32: RemoteKey] = [
        0x66: .power, 0x3E: .voice,
        0x52: .up, 0x51: .down, 0x50: .left, 0x4F: .right, 0x28: .ok,
        0xF1: .back, 0x4A: .home, 0x65: .menu, 0x35: .tv,
        0x80: .volUp, 0x81: .volDown,
    ]
}

/// hidutil 设备级重映射：把遥控器按键换成系统零副作用的中转键，
/// 再由 CGEventTap 捕获并吞掉。macOS 不允许用户态 seize 蓝牙键盘，
/// 这是唯一实测可行的接管路径（与 MiRemote 一致）。
enum KeyRemapper {

    static var log: ((String) -> Void)?

    static let vendorID = 0x2717
    static let productID = 0x32B8

    static var matching: String {
        "{\"VendorID\":\(String(format: "0x%X", vendorID)),\"ProductID\":\(String(format: "0x%X", productID))}"
    }

    /// (遥控器原始 usage, 中转键 usage, macOS keycode, 逻辑键)
    static let table: [(src: UInt32, dst: UInt32, keycode: Int64, key: RemoteKey)] = [
        // 方向键
        (0x52, 0x6E, 80,  .up),     // F19
        (0x51, 0x6F, 90,  .down),   // F20
        (0x50, 0x68, 105, .left),   // F13
        (0x4F, 0x53, 71,  .right),  // Keypad Clear（macOS 无 NumLock，零默认行为）
        (0x28, 0x6D, 79,  .ok),     // F18
        (0x4A, 0x69, 107, .home),   // F14
        (0x65, 0x6A, 113, .menu),   // F15
        (0x35, 0x6B, 106, .tv),     // F16
        (0x66, 0x6C, 64,  .power),  // F17
        // 音量键保持系统原生（不重映射）：即使 Tap 失效也不会漏出字符，
        // Secure Input 期间也照常调音量。
    ]

    /// 只静默、不送引擎的映射：语音键同时上报键盘 F5，映射到 F21（macOS 无键码）
    /// 防止在终端里漏出 ESC[15~ 序列。真正的语音生命周期由 ATVV BLE 通道驱动。
    static let silentTable: [(src: UInt32, dst: UInt32)] = [
        (0x3E, 0x70),
    ]

    /// back(0xF1) 超出标准键盘 usage 范围，hidutil 不认、系统也忽略，
    /// 由 IOHID 监听通道直接读取。
    static var keycodeMap: [Int64: RemoteKey] {
        Dictionary(uniqueKeysWithValues: table.map { ($0.keycode, $0.key) })
    }

    private static var allMappings: [(src: UInt32, dst: UInt32)] {
        table.map { ($0.src, $0.dst) } + silentTable
    }

    // MARK: - hidutil

    private static let hidutilLock = NSLock()
    /// install 前保存的设备原有映射（剔除本程序条目），uninstall 时恢复。
    private static var savedForeign: [(src: UInt64, dst: UInt64)]?

    @discardableResult
    private static func runHidutil(_ args: [String], capture: Bool = false) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = capture ? pipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            log?("hidutil 启动失败: \(error)")
            return (false, "")
        }
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }

    /// 解析 `hidutil property --get UserKeyMapping` 的 plist 风格输出。
    static func parseUserKeyMapping(_ text: String) -> [(src: UInt64, dst: UInt64)]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if !trimmed.contains("{") {
            if trimmed.contains("(null)") { return [] }
            if let open = trimmed.firstIndex(of: "("), let close = trimmed.lastIndex(of: ")"),
               open < close,
               trimmed[trimmed.index(after: open)..<close]
                   .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            return nil
        }
        var pairs: [(src: UInt64, dst: UInt64)] = []
        var rest = Substring(trimmed)
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}") else { return nil }
            let block = rest[open...close]
            guard let src = number(after: "HIDKeyboardModifierMappingSrc", in: block),
                  let dst = number(after: "HIDKeyboardModifierMappingDst", in: block) else { return nil }
            pairs.append((src, dst))
            rest = rest[rest.index(after: close)...]
        }
        return pairs
    }

    private static func number(after key: String, in block: Substring) -> UInt64? {
        guard let keyRange = block.range(of: key),
              let equals = block[keyRange.upperBound...].firstIndex(of: "=") else { return nil }
        var value = block[block.index(after: equals)...]
        value = value.drop(while: { $0 == " " || $0 == "\t" })
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            let digits = value.dropFirst(2).prefix(while: { $0.isHexDigit })
            return UInt64(digits, radix: 16)
        }
        let digits = value.prefix(while: { $0.isNumber })
        return UInt64(digits)
    }

    private static func entryJSON(src: UInt64, dst: UInt64) -> String {
        "{\"HIDKeyboardModifierMappingSrc\":\(src),\"HIDKeyboardModifierMappingDst\":\(dst)}"
    }

    static var ourSourceCodes: Set<UInt64> {
        Set(allMappings.map { 0x700000000 + UInt64($0.src) })
    }

    /// 安装映射（幂等）。先取快照，保留第三方条目，再合并本程序条目。
    /// 快照读不到时拒绝安装，绝不覆盖设备上已有的映射。
    @discardableResult
    static func install() -> Bool {
        hidutilLock.lock(); defer { hidutilLock.unlock() }
        let current = runHidutil(["property", "--matching", matching, "--get", "UserKeyMapping"], capture: true)
        guard current.ok, let pairs = parseUserKeyMapping(current.output) else {
            log?("hidutil 读取现状失败，跳过安装")
            return false
        }
        let ours = ourSourceCodes
        if savedForeign == nil {
            savedForeign = pairs.filter { !ours.contains($0.src) }
        }
        var merged = (savedForeign ?? []).map { entryJSON(src: $0.src, dst: $0.dst) }
        merged.append(contentsOf: allMappings.map { entryJSON(src: 0x700000000 + UInt64($0.src),
                                                              dst: 0x700000000 + UInt64($0.dst)) })
        let json = "{\"UserKeyMapping\":[\(merged.joined(separator: ","))]}"
        let result = runHidutil(["property", "--matching", matching, "--set", json])
        if !result.ok { log?("hidutil 安装映射失败") }
        return result.ok
    }

    static func isInstalled() -> Bool {
        let result = runHidutil(["property", "--matching", matching, "--get", "UserKeyMapping"], capture: true)
        guard result.ok, let pairs = parseUserKeyMapping(result.output) else { return false }
        let current = Set(pairs.map { $0.src })
        return ourSourceCodes.isSubset(of: current)
    }

    /// 卸载：优先恢复安装前快照；无快照时只剔除本程序条目。
    @discardableResult
    static func uninstall() -> Bool {
        hidutilLock.lock(); defer { hidutilLock.unlock() }
        if let foreign = savedForeign {
            let entries = foreign.map { entryJSON(src: $0.src, dst: $0.dst) }
            let ok = runHidutil(["property", "--matching", matching,
                                 "--set", #"{"UserKeyMapping":[\#(entries.joined(separator: ","))]}"#]).ok
            if ok { savedForeign = nil } else { log?("hidutil 恢复原映射失败") }
            return ok
        }
        let current = runHidutil(["property", "--matching", matching, "--get", "UserKeyMapping"], capture: true)
        guard current.ok, let pairs = parseUserKeyMapping(current.output) else { return false }
        let ours = ourSourceCodes
        let entries = pairs.filter { !ours.contains($0.src) }.map { entryJSON(src: $0.src, dst: $0.dst) }
        let ok = runHidutil(["property", "--matching", matching,
                             "--set", #"{"UserKeyMapping":[\#(entries.joined(separator: ","))]}"#]).ok
        if !ok { log?("hidutil 清理映射失败") }
        return ok
    }
}
