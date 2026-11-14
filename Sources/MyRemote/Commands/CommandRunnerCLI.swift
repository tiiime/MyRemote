import Foundation

/// 调试用：`MyRemote --test-command "打开 dsh" [--execute]`
/// 只做匹配并打印结果；加 --execute 才真正执行动作。
enum CommandRunnerCLI {

    static func run(text: String, execute: Bool) -> Bool {
        let config = ConfigStore.load()
        guard let rule = CommandMatcher.firstMatch(text, rules: config.commandRules) else {
            print("没有匹配的指令：\(text)")
            let names = config.commandRules.filter(\.enabled).map(\.name)
            if !names.isEmpty { print("可用指令：\(names.joined(separator: " / "))") }
            return false
        }

        print("命中：\(rule.name)")
        print("动作：\(rule.action.summary)")
        guard execute else { return true }

        var done = false
        var success = false
        CommandRunner.execute(rule.action, input: text) { ok, message in
            print((ok ? "✓ " : "✗ ") + message)
            success = ok
            done = true
        }
        while !done {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        return success
    }
}
