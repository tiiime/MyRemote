import Foundation
import CryptoKit

/// 本机 DSH（DeepSeek Harness）的凭据与浏览器会话 Cookie。
///
/// DSH 的 Web 服务只接受「浏览器会话 Cookie」或「API Peer Cookie」。桌面端自带的
/// launch token 只存在于 Host 进程内，外部程序拿不到；因此这里改用本机凭据文件里的
/// `client-connection/browser-session` 密钥，按 DSH 的格式签一个浏览器 Cookie，
/// 以本机 owner 身份调用 `localhost` 上的 `/api`（数据不出本机）。
enum DSHCredential {

    static var dshHome: URL {
        if let home = ProcessInfo.processInfo.environment["DSH_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh", isDirectory: true)
    }

    static var credentialsURL: URL {
        dshHome.appendingPathComponent(".credentials.yaml")
    }

    /// 读取 32 字节 HMAC 密钥（base64url）。
    static func browserSessionSecret() -> Data? {
        guard let text = try? String(contentsOf: credentialsURL, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        var blockIndent: Int?
        var secretValue: String?

        for line in lines {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("client-connection/browser-session:") {
                blockIndent = indent
                continue
            }
            guard let base = blockIndent else { continue }
            if trimmed.isEmpty { continue }
            if indent <= base {
                blockIndent = nil
                continue
            }
            if trimmed.hasPrefix("secret:") {
                secretValue = trimmed.dropFirst("secret:".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                break
            }
        }

        guard let value = secretValue, let data = base64URLDecode(value), data.count == 32 else {
            return nil
        }
        return data
    }

    /// 生成 `dsh-auth-<hash>=v1.<payload>.<sig>` 浏览器会话 Cookie。
    static func browserCookie(authority: String, now: Date = Date()) -> String? {
        guard let secret = browserSessionSecret() else { return nil }
        return makeBrowserCookie(secret: secret, authority: authority, now: now)
    }

    /// 用给定密钥签名（自检/测试可直接调用）。
    static func makeBrowserCookie(secret: Data, authority: String, now: Date) -> String {
        let issuedAt = Int(now.timeIntervalSince1970 * 1000)
        let expiresAt = issuedAt + 86_400_000   // 1 天，远小于 DSH 默认 30 天上限
        let payload: [String: Any] = [
            "version": 1,
            "authority": authority,
            "issuedAt": issuedAt,
            "expiresAt": expiresAt,
        ]
        let json = try! JSONSerialization.data(withJSONObject: payload)
        let text = String(decoding: json, as: UTF8.self)
        let body = base64URL(Data(text.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(body.utf8),
                                                  using: SymmetricKey(data: secret))
        let name = "dsh-auth-" + base64URL(Data(SHA256.hash(data: Data(authority.utf8))))
        return "\(name)=v1.\(body).\(base64URL(Data(mac)))"
    }

    // MARK: - base64url

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    static func base64URLDecode(_ value: String) -> Data? {
        var text = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - text.count % 4) % 4
        text += String(repeating: "=", count: padding)
        return Data(base64Encoded: text)
    }
}
