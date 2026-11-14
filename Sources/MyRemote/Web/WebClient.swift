import Foundation
import Network
import CryptoKit

/// 单个 HTTPS 连接：先处理 HTTP，再升级为 WebSocket。
final class WebClient {

    let id = UUID()
    private weak var server: WebRemoteServer?
    private let connection: NWConnection
    private var buffer = Data()
    private var upgraded = false
    private var closed = false
    private var voiceActive = false

    init(connection: NWConnection, server: WebRemoteServer) {
        self.connection = connection
        self.server = server
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
    }

    func start() {
        connection.start(queue: server?.queue ?? .main)
        receive()
    }

    func close() {
        guard !closed else { return }
        closed = true
        if voiceActive {
            voiceActive = false
            server?.didStopVoice()
        }
        connection.cancel()
        server?.remove(self)
    }

    private func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }
            if error != nil || complete {
                self.close()
                return
            }
            self.receive()
        }
    }

    private func processBuffer() {
        if !upgraded {
            processHTTP()
        }
        if upgraded, !closed {
            processFrames()
        }
    }

    // MARK: - HTTP

    private func processHTTP() {
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
        let headerData = buffer[..<headerRange.lowerBound]
        buffer.removeSubrange(buffer.startIndex..<headerRange.upperBound)

        let text = String(decoding: headerData, as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            close()
            return
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            sendHTTP(status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8))
            return
        }
        let method = parts[0].uppercased()
        let target = parts[1]
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let components = URLComponents(string: target)
        let path = components?.path ?? target
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value

        if headers["upgrade"]?.lowercased() == "websocket",
           headers["connection"]?.lowercased().contains("upgrade") == true {
            upgradeWebSocket(headers: headers, token: token)
            return
        }

        guard method == "GET" else {
            sendHTTP(status: "405 Method Not Allowed", contentType: "text/plain", body: Data("Method Not Allowed".utf8))
            return
        }

        switch path {
        case "/", "/index.html":
            sendHTTP(status: "200 OK", contentType: "text/html; charset=utf-8",
                     body: Data(WebPage.html.utf8), extra: ["Cache-Control: no-store"])
        case "/ca.crt":
            if let data = server?.caCertificateData() {
                sendHTTP(status: "200 OK", contentType: "application/x-x509-ca-cert",
                         body: data,
                         extra: ["Content-Disposition: attachment; filename=\"MyRemote-CA.crt\"",
                                 "Cache-Control: no-store"])
            } else {
                sendHTTP(status: "404 Not Found", contentType: "text/plain", body: Data("No CA".utf8))
            }
        case "/favicon.ico":
            sendHTTP(status: "204 No Content", contentType: "image/x-icon", body: Data())
        default:
            sendHTTP(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
        }
    }

    private func sendHTTP(status: String, contentType: String, body: Data, extra: [String] = []) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for line in extra { head += line + "\r\n" }
        head += "\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    // MARK: - WebSocket

    private func upgradeWebSocket(headers: [String: String], token: String?) {
        guard let server,
              let key = headers["sec-websocket-key"],
              let expected = server.token.nilIfEmpty,
              let supplied = token, !supplied.isEmpty,
              constantTimeEquals(supplied, expected) else {
            sendHTTP(status: "403 Forbidden", contentType: "text/plain", body: Data("Invalid token".utf8))
            return
        }
        let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)))
            .base64EncodedString()
        let response = """
        HTTP/1.1 101 Switching Protocols\r\n\
        Upgrade: websocket\r\n\
        Connection: Upgrade\r\n\
        Sec-WebSocket-Accept: \(accept)\r\n\
        \r\n
        """
        upgraded = true
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
        sendJSON(["type": "state", "mode": server.modeForClient().rawValue])
    }

    private func processFrames() {
        while !closed {
            guard buffer.count >= 2 else { return }
            let bytes = [UInt8](buffer)
            let fin = bytes[0] & 0x80 != 0
            let opcode = bytes[0] & 0x0F
            let masked = bytes[1] & 0x80 != 0
            var length = Int(bytes[1] & 0x7F)
            var offset = 2

            if length == 126 {
                guard bytes.count >= 4 else { return }
                length = Int(bytes[2]) << 8 | Int(bytes[3])
                offset = 4
            } else if length == 127 {
                guard bytes.count >= 10 else { return }
                var value: UInt64 = 0
                for index in 2..<10 { value = value << 8 | UInt64(bytes[index]) }
                guard value <= 2 * 1024 * 1024 else { close(); return }
                length = Int(value)
                offset = 10
            }

            let maskLength = masked ? 4 : 0
            let payloadLength = length
            guard bytes.count >= offset + maskLength + payloadLength else { return }
            var payload = Data(bytes[(offset + maskLength)..<(offset + maskLength + payloadLength)])
            if masked {
                let mask = Array(bytes[offset..<(offset + 4)])
                payload = Data(payload.enumerated().map { index, byte in
                    byte ^ mask[index % 4]
                })
            }
            buffer.removeFirst(offset + maskLength + payloadLength)

            guard fin else { continue }
            switch opcode {
            case 0x1:
                handleText(payload)
            case 0x2:
                if voiceActive { server?.didReceiveVoiceData(payload) }
            case 0x8:
                sendFrame(opcode: 0x8, payload: Data())
                close()
                return
            case 0x9:
                sendFrame(opcode: 0xA, payload: payload)
            case 0xA:
                break
            default:
                break
            }
        }
    }

    private func handleText(_ payload: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "key":
            if let raw = object["key"] as? String, let key = RemoteKey(rawValue: raw) {
                server?.didReceiveKey(key)
            }
        case "mode":
            if let raw = object["mode"] as? String, let mode = VoiceMode(rawValue: raw) {
                server?.didChangeMode(mode)
            }
        case "voice_start":
            guard !voiceActive else { return }
            let mode = (object["mode"] as? String).flatMap(VoiceMode.init(rawValue:)) ?? .forward
            if let server, server.didStartVoice(mode, client: self) {
                voiceActive = true
            }
        case "voice_stop":
            guard voiceActive else { return }
            voiceActive = false
            server?.didStopVoice()
        case "ping":
            sendJSON(["type": "pong"])
        default:
            break
        }
    }

    func sendJSON(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        sendFrame(opcode: 0x1, payload: data)
    }

    private func sendFrame(opcode: UInt8, payload: Data) {
        guard !closed else { return }
        var header: [UInt8] = [0x80 | opcode]
        if payload.count < 126 {
            header.append(UInt8(payload.count))
        } else if payload.count <= 0xFFFF {
            header.append(126)
            header.append(UInt8((payload.count >> 8) & 0xFF))
            header.append(UInt8(payload.count & 0xFF))
        } else {
            header.append(127)
            let count = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                header.append(UInt8((count >> UInt64(shift)) & 0xFF))
            }
        }
        var frame = Data(header)
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for index in a.indices { diff |= a[index] ^ b[index] }
        return diff == 0
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
