import Foundation

/// 开发用：不启动菜单栏 App，只启动 Web 遥控器，便于用 curl / 浏览器验证 HTTPS/WebSocket。
enum WebRunner {
    static func run() -> Never {
        let server = WebRemoteServer()
        server.onState = { state in
            switch state.phase {
            case .starting:
                print("web: starting")
            case .running:
                print("web: \(state.url)")
                print("ca:  \(state.caPath)")
                fflush(stdout)
            case .failed(let message):
                print("web: failed \(message)")
                fflush(stdout)
            case .stopped:
                print("web: stopped")
            }
        }
        server.onKey = { key in
            print("key: \(key.rawValue)")
            fflush(stdout)
        }
        server.onMode = { mode in
            print("mode: \(mode.rawValue)")
            fflush(stdout)
        }
        server.onVoiceStart = { _ in true }
        server.onVoiceData = { data in
            print("pcm: \(data.count) bytes")
            fflush(stdout)
        }
        server.onVoiceStop = {
            print("voice: stop")
            fflush(stdout)
        }
        server.currentMode = { .forward }
        server.start(port: 47823)
        RunLoop.main.run()
        exit(0)
    }
}
