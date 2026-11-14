import Foundation

/// 一条本机 DSH 会话（工作区目录 + 会话标题）。
struct DSHSessionInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let workspacePath: String
    let updatedAt: Date?

    var displayName: String {
        title.isEmpty ? "未命名会话" : title
    }

    var workspaceName: String {
        URL(fileURLWithPath: workspacePath).lastPathComponent
    }

    var label: String {
        workspaceName.isEmpty ? displayName : "\(displayName) · \(workspaceName)"
    }
}

/// 直接读取 DSH 的本地存储，列出工作区与会话标题（不依赖 DSH 进程）。
enum DSHSessionStore {

    static var storagesDirectory: URL {
        DSHCredential.dshHome.appendingPathComponent("storages", isDirectory: true)
    }

    private static var workspaceFile: URL {
        storagesDirectory.appendingPathComponent("workspace.json")
    }

    private static var projCacheDirectory: URL {
        storagesDirectory.appendingPathComponent("session_projcache/sessions", isDirectory: true)
    }

    static func sessions() -> [DSHSessionInfo] {
        let archived = archivedSessionIds()
        var workspaceBySession: [String: String] = [:]
        loadWorkspaces(into: &workspaceBySession)

        let files = (try? FileManager.default.contentsOfDirectory(
            at: projCacheDirectory, includingPropertiesForKeys: nil)) ?? []

        var result: [DSHSessionInfo] = []
        for file in files where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("session-") {
            let id = file.deletingPathExtension().lastPathComponent
            guard !archived.contains(id),
                  let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let record = root["record"] as? [String: Any] else { continue }

            let identity = record["identity"] as? [String: Any] ?? [:]
            let rows = record["rows"] as? [String: Any] ?? [:]
            let title = ((rows["title"] as? [String: Any])?["val"] as? String) ?? ""
            let metadata = (rows["sessionListMetadata"] as? [String: Any])?["val"] as? [String: Any]
            let lastPromptAt = metadata?["lastPromptAt"] as? Double
            let cwd = identity["cwd"] as? String ?? ""

            let workspacePath = workspaceBySession[id] ?? cwd
            let updatedAt = lastPromptAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            result.append(DSHSessionInfo(id: id, title: title,
                                         workspacePath: workspacePath,
                                         updatedAt: updatedAt))
        }

        return result.sorted { lhs, rhs in
            (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
    }

    /// 按标题找会话；`preferWorkspaceContains` 用于在同名会话里优先某个工作区（如 MyRemote）。
    static func resolveSession(title: String,
                               preferWorkspaceContains: String? = "MyRemote") -> DSHSessionInfo? {
        let needle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        let matches = sessions().filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
        }
        guard !matches.isEmpty else { return nil }
        if let prefer = preferWorkspaceContains?.lowercased(), !prefer.isEmpty {
            if let preferred = matches.first(where: { $0.workspacePath.lowercased().contains(prefer) }) {
                return preferred
            }
        }
        return matches.first
    }

    // MARK: - 解析

    private static func archivedSessionIds() -> Set<String> {
        guard let data = try? Data(contentsOf: workspaceFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let global = root["global"] as? [String: Any],
              let archived = global["archivedSessionIds"] as? [String] else { return [] }
        return Set(archived)
    }

    private static func loadWorkspaces(into map: inout [String: String]) {
        guard let data = try? Data(contentsOf: workspaceFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tables = root["tables"] as? [String: Any],
              let workspaces = tables["workspaces"] as? [String: Any] else { return }

        for case let workspace as [String: Any] in workspaces.values {
            guard let path = workspace["path"] as? String else { continue }
            let ids = workspace["sessionIds"] as? [String] ?? []
            for id in ids { map[id] = path }
        }
    }
}
