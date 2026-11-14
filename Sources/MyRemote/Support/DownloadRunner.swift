import Foundation

/// 命令行模型下载：`MyRemote --download-model`（用于首次配置或排障）。
enum DownloadRunner {

    /// 用 316KB 的 tokens.txt 切成 4 段，验证 Range 下载与拼装。
    static func runChunkedSelfTest() -> Bool {
        guard let base = URL(string: "https://hf-mirror.com/\(AppConfig().modelRepo)/resolve/main/") else { return false }
        let url = base.appendingPathComponent("tokens.txt")
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("myremote-tokens-selftest.txt")

        guard let size = ModelManager.contentLengthForTest(url) else {
            print("无法获取文件大小")
            return false
        }
        print("测试文件大小：\(size) 字节，单段下载")
        let result = ModelManager.selfTestChunked(url: url, size: size, chunks: 1, destination: destination)
        switch result {
        case .success:
            let actual = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            try? FileManager.default.removeItem(at: destination)
            print(actual == size ? "分段下载自测通过（\(actual) 字节）" : "大小不符：\(actual)/\(size)")
            return actual == size
        case .failure(let error):
            print("分段下载自测失败：\(error.localizedDescription)")
            return false
        }
    }

    static func run() -> Bool {
        let manager = ModelManager(repository: AppConfig().modelRepo,
                                   mirror: AppConfig().hfMirror,
                                   directory: ConfigStore.modelDirectory)
        Log.info("模型目录：\(ConfigStore.modelDirectory.path)")

        var done = false
        var success = false
        var lastPercent = -1
        manager.install(progress: { fraction, message in
            let percent = Int(fraction * 100)
            guard percent != lastPercent else { return }
            lastPercent = percent
            FileHandle.standardError.write(Data(String(format: "[%3d%%] %@\n", percent, message).utf8))
        }, completion: { result in
            switch result {
            case .success:
                success = true
                print("模型已就绪：\(manager.modelURL.path)")
            case .failure(let error):
                print("下载失败：\(error.localizedDescription)")
            }
            done = true
        })

        while !done {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        return success
    }
}
