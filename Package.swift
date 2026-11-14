// swift-tools-version:6.0
import PackageDescription
import Foundation

// Vendor 目录里放 sherpa-onnx 的 dylib（由 scripts/fetch-sherpa.sh 从 PyPI wheel 提取）。
// 这里用绝对路径生成 -L，避免 SwiftPM 把相对路径解析到构建目录。
let vendorLib = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Vendor/sherpa/lib")
    .path

let package = Package(
    name: "MyRemote",
    platforms: [.macOS(.v14)],
    targets: [
        // sherpa-onnx C API（header-only 模块，链接 Vendor/sherpa/lib 下的 dylib）。
        .systemLibrary(
            name: "CSherpa",
            path: "Sources/CSherpa"
        ),
        .executableTarget(
            name: "MyRemote",
            dependencies: ["CSherpa"],
            path: "Sources/MyRemote",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", vendorLib,
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
                ])
            ]
        ),
    ]
)
