import Foundation
import Network
import Security
import CryptoKit

struct WebRemoteState: Equatable {
    enum Phase: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    var phase: Phase = .stopped
    var url: String = ""
    var caPath: String = ""
    var error: String = ""
}

/// 局域网 Web 遥控器：HTTPS 静态页面 + WebSocket 按键/语音通道。
/// 证书由本地 CA 签发，手机信任一次 CA 后即可使用麦克风。
final class WebRemoteServer {

    var onState: ((WebRemoteState) -> Void)?
    var onKey: ((RemoteKey) -> Void)?
    var onMode: ((VoiceMode) -> Void)?
    var onVoiceStart: ((VoiceMode) -> Bool)?
    var onVoiceData: ((Data) -> Void)?
    var onVoiceStop: (() -> Void)?
    var currentMode: (() -> VoiceMode)?

    let queue = DispatchQueue(label: "com.wario.MyRemote.webremote")
    private var listener: NWListener?
    private var clients: [UUID: WebClient] = [:]
    private(set) var state = WebRemoteState()
    private(set) var token = ""
    private var caURL: URL?

    private static let defaultPort: UInt16 = 47823

    // MARK: - 生命周期

    func start(port: UInt16 = WebRemoteServer.defaultPort) {
        queue.async { [weak self] in
            self?.startLocked(port: port)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for client in self.clients.values { client.close() }
            self.clients.removeAll()
            self.state = WebRemoteState()
            self.emitState()
        }
    }

    private func startLocked(port: UInt16) {
        guard listener == nil else { return }
        state = WebRemoteState(phase: .starting)
        emitState()

        let ips = Self.localIPv4Addresses()
        let certDirectory: URL
        if let override = ProcessInfo.processInfo.environment["MYREMOTE_WEB_DIR"], !override.isEmpty {
            certDirectory = URL(fileURLWithPath: override)
        } else {
            certDirectory = ConfigStore.directory.appendingPathComponent("WebRemote", isDirectory: true)
        }
        let material: WebCertificateMaterial
        do {
            material = try WebCertificate.ensure(directory: certDirectory,
                                                 ips: ips.isEmpty ? ["127.0.0.1"] : ips)
        } catch {
            fail(error.localizedDescription)
            return
        }
        caURL = material.caURL

        guard let secIdentity = sec_identity_create(material.identity) else {
            fail("无法加载本地 HTTPS 身份")
            return
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            fail("Web 遥控器端口无效")
            return
        }
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            fail("端口 \(port) 启动失败：\(error.localizedDescription)")
            return
        }

        token = Self.makeToken()
        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                let host = ips.first ?? "127.0.0.1"
                let url = "https://\(host):\(port)/?token=\(self.token)"
                self.state = WebRemoteState(phase: .running, url: url,
                                            caPath: material.caURL.path, error: "")
                self.emitState()
                Log.info("Web 遥控器已启动：\(url)")
            case .failed(let error):
                self.fail("Web 遥控器监听失败：\(error.localizedDescription)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.queue.async {
                let client = WebClient(connection: connection, server: self)
                self.clients[client.id] = client
                client.start()
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func fail(_ message: String) {
        listener?.cancel()
        listener = nil
        state = WebRemoteState(phase: .failed(message), error: message)
        emitState()
        Log.error(message)
    }

    private func emitState() {
        let snapshot = state
        DispatchQueue.main.async { [weak self] in
            self?.onState?(snapshot)
        }
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 客户端管理

    func remove(_ client: WebClient) {
        queue.async { [weak self] in
            self?.clients.removeValue(forKey: client.id)
        }
    }

    func didReceiveKey(_ key: RemoteKey) {
        onKey?(key)
    }

    func didChangeMode(_ mode: VoiceMode) {
        onMode?(mode)
    }

    @discardableResult
    func didStartVoice(_ mode: VoiceMode, client: WebClient) -> Bool {
        let ok = onVoiceStart?(mode) ?? false
        if ok {
            client.sendJSON(["type": "voice_started", "mode": mode.rawValue])
        } else {
            client.sendJSON(["type": "error", "message": "Mac 端无法开始录音，请检查语音共享/模型状态"])
        }
        return ok
    }

    func caCertificateData() -> Data? {
        guard let caURL else { return nil }
        return try? Data(contentsOf: caURL)
    }

    func didReceiveVoiceData(_ data: Data) {
        onVoiceData?(data)
    }

    func didStopVoice() {
        onVoiceStop?()
    }

    func sendTranscript(_ text: String) {
        queue.async { [weak self] in
            guard let self else { return }
            for client in self.clients.values {
                client.sendJSON(["type": "transcript", "text": text])
            }
        }
    }

    func sendMode(_ mode: VoiceMode) {
        queue.async { [weak self] in
            guard let self else { return }
            for client in self.clients.values {
                client.sendJSON(["type": "state", "mode": mode.rawValue])
            }
        }
    }

    func sendError(_ message: String) {
        queue.async { [weak self] in
            guard let self else { return }
            for client in self.clients.values {
                client.sendJSON(["type": "error", "message": message])
            }
        }
    }

    func modeForClient() -> VoiceMode {
        currentMode?() ?? .forward
    }

    // MARK: - 局域网地址

    static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return result }
        defer { freeifaddrs(addrs) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = interface.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            guard status == 0 else { continue }
            let value = String(cString: host)
            if !value.isEmpty, !result.contains(value) {
                result.append(value)
            }
        }
        result.sort { lhs, rhs in
            if lhs.hasPrefix("192.168.") != rhs.hasPrefix("192.168.") {
                return lhs.hasPrefix("192.168.")
            }
            return lhs < rhs
        }
        return result
    }
}
