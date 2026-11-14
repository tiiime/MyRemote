import Foundation
import Security

/// 本地 HTTPS 证书：长期稳定的本地 CA + 每次启动重新签发的服务器证书。
/// 手机只需信任一次 CA；服务器私钥导入内存后立即删除，不长期落盘。
struct WebCertificateMaterial {
    let caURL: URL
    let identity: SecIdentity
    let ips: [String]
}

enum WebCertificateError: LocalizedError {
    case opensslFailed(String)
    case importFailed(String)
    case missingFiles

    var errorDescription: String? {
        switch self {
        case .opensslFailed(let message): return "生成本地 HTTPS 证书失败：\(message)"
        case .importFailed(let message): return "读取本地 HTTPS 证书失败：\(message)"
        case .missingFiles: return "本地 HTTPS 证书文件不完整"
        }
    }
}

enum WebCertificate {

    static func ensure(directory: URL, ips: [String]) throws -> WebCertificateMaterial {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var guardedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? guardedDirectory.setResourceValues(values)

        let caURL = directory.appendingPathComponent("ca.crt")
        let p12URL = directory.appendingPathComponent("server.p12")
        let sanURL = directory.appendingPathComponent("server.san")
        let serverKey = directory.appendingPathComponent("server.key")
        let serverCSR = directory.appendingPathComponent("server.csr")
        let wanted = Set(ips + ["127.0.0.1"])

        try generateCAIfNeeded(directory: directory)
        let password = randomPassword()
        try generateServer(directory: directory, ips: Array(wanted).sorted(),
                           sanURL: sanURL, password: password)
        guard FileManager.default.fileExists(atPath: caURL.path),
              FileManager.default.fileExists(atPath: p12URL.path) else {
            throw WebCertificateError.missingFiles
        }

        let identity: SecIdentity
        do {
            identity = try loadIdentity(p12URL, password: password)
        } catch {
            throw WebCertificateError.importFailed(error.localizedDescription)
        }

        // 服务器证书私钥已经进入 SecIdentity 内存；不把明文私钥长期留在磁盘。
        for file in [serverKey, serverCSR, p12URL] {
            try? FileManager.default.removeItem(at: file)
        }
        return WebCertificateMaterial(caURL: caURL, identity: identity, ips: ips)
    }

    private static func randomPassword() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func generateCAIfNeeded(directory: URL) throws {
        let openssl = "/usr/bin/openssl"
        let caKey = directory.appendingPathComponent("ca.key")
        let caCert = directory.appendingPathComponent("ca.crt")
        let caConfig = directory.appendingPathComponent("ca.cnf")
        let fm = FileManager.default
        if fm.fileExists(atPath: caKey.path) && fm.fileExists(atPath: caCert.path) {
            return
        }

        let caConfigText = """
        [req]
        distinguished_name = dn
        x509_extensions = v3_ca
        prompt = no
        [dn]
        CN = MyRemote Local CA
        [v3_ca]
        basicConstraints = critical,CA:TRUE
        keyUsage = critical,keyCertSign,cRLSign
        subjectKeyIdentifier = hash
        """
        try caConfigText.write(to: caConfig, atomically: true, encoding: .utf8)
        try? fm.removeItem(at: caKey)
        try? fm.removeItem(at: caCert)
        try run(openssl, [
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "3650", "-nodes",
            "-keyout", caKey.path, "-out", caCert.path, "-config", caConfig.path
        ])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: caKey.path)
    }

    private static func generateServer(directory: URL, ips: [String], sanURL: URL,
                                      password: String) throws {
        let openssl = "/usr/bin/openssl"
        let caKey = directory.appendingPathComponent("ca.key")
        let caCert = directory.appendingPathComponent("ca.crt")
        let serverKey = directory.appendingPathComponent("server.key")
        let serverCSR = directory.appendingPathComponent("server.csr")
        let serverCert = directory.appendingPathComponent("server.crt")
        let serverP12 = directory.appendingPathComponent("server.p12")
        let serverExt = directory.appendingPathComponent("server.ext")
        let caSerial = directory.appendingPathComponent("ca.srl")
        let fm = FileManager.default
        guard fm.fileExists(atPath: caKey.path), fm.fileExists(atPath: caCert.path) else {
            throw WebCertificateError.missingFiles
        }

        let sans = ips.map { "IP:\($0)" }.joined(separator: ",") + ",DNS:localhost"
        let extText = """
        basicConstraints = CA:FALSE
        keyUsage = digitalSignature,keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = \(sans)
        """
        try extText.write(to: serverExt, atomically: true, encoding: .utf8)
        try? fm.removeItem(at: serverKey)
        try? fm.removeItem(at: serverCSR)
        try? fm.removeItem(at: serverCert)
        try? fm.removeItem(at: serverP12)

        try run(openssl, [
            "req", "-newkey", "rsa:2048", "-sha256", "-nodes",
            "-keyout", serverKey.path, "-out", serverCSR.path,
            "-subj", "/CN=MyRemote Web"
        ])
        try run(openssl, [
            "x509", "-req", "-in", serverCSR.path,
            "-CA", caCert.path, "-CAkey", caKey.path,
            "-CAserial", caSerial.path, "-CAcreateserial",
            "-out", serverCert.path, "-days", "397", "-sha256", "-extfile", serverExt.path
        ])
        try run(openssl, [
            "pkcs12", "-export", "-out", serverP12.path,
            "-inkey", serverKey.path, "-in", serverCert.path, "-certfile", caCert.path,
            "-passout", "pass:\(password)"
        ])

        for file in [serverKey, serverP12] {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        try (ips.joined(separator: ",")).write(to: sanURL, atomically: true, encoding: .utf8)
    }

    private static func loadIdentity(_ p12URL: URL, password: String) throws -> SecIdentity {
        let data = try Data(contentsOf: p12URL)
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        let status = SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let raw = array.first?[kSecImportItemIdentity as String] else {
            throw WebCertificateError.importFailed("SecPKCS12Import status \(status)")
        }
        return raw as! SecIdentity
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw WebCertificateError.opensslFailed(message.isEmpty ? "openssl exit \(process.terminationStatus)" : message)
        }
    }
}
