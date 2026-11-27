import Foundation
import PMSetShared

/// Helper 的版本号，必须与 App 端 PrivilegedHelperManager.helperVersion 一致。
/// 1.1.0：命令语义变更——从「任意 shell 命令」改为「白名单 pmset 命令」，不再经过 shell。
let kHelperVersion = "1.1.0"

/// 允许连接的调用者 requirement：必须是本 App（identifier 匹配）。
/// 通过 NSXPCConnection.setCodeSigningRequirement(_:) 设置，系统自动验证。
private let kAllowedCallerRequirement = "identifier \"local.pmset.app\""

// MARK: - 命令白名单

/// 唯一允许执行的可执行文件。
private let kPmsetPath = "/usr/bin/pmset"

/// 允许通过 `-a` 写入的参数键（与 App 端 PowerKey.allKeys 一致）。
private let kAllowedKeys: Set<String> = [
    "disablesleep",
    "sleep",
    "displaysleep",
    "disksleep",
    "hibernatemode",
    "standby",
    "autopoweroff",
    "tcpkeepalive",
    "womp"
]

/// 允许的无参数子命令。
private let kAllowedSubcommands: Set<String> = ["restoredefaults", "sleepnow"]

/// 单条命令的校验结果。
private enum CommandValidation {
    /// 通过校验，附带拆分后的参数（不含可执行文件路径）
    case accepted([String])
    /// 被拒绝，附带中文原因
    case rejected(String)
}

/// 整串严格校验一条命令：
/// - `/usr/bin/pmset -a <key> <value>`，key 在白名单内，value 为十进制非负整数
/// - `/usr/bin/pmset restoredefaults`
/// - `/usr/bin/pmset sleepnow`
///
/// 只允许单空格分隔，任何多余空白、shell 元字符、其他可执行文件或其他参数都会导致拒绝。
private func validate(_ command: String) -> CommandValidation {
    let parts = command
        .split(separator: " ", omittingEmptySubsequences: false)
        .map(String.init)

    guard parts.first == kPmsetPath else {
        return .rejected("只允许执行 \(kPmsetPath)，收到：\(command)")
    }
    if parts.contains(where: { $0.isEmpty }) {
        return .rejected("命令格式不合法（存在多余空格）：\(command)")
    }

    switch parts.count {
    case 2:
        guard kAllowedSubcommands.contains(parts[1]) else {
            return .rejected("不允许的 pmset 子命令：\(parts[1])（仅允许 restoredefaults / sleepnow）")
        }
        return .accepted([parts[1]])

    case 4:
        guard parts[1] == "-a" else {
            return .rejected("只允许使用 -a 写入全局配置，收到：\(parts[1])")
        }
        guard kAllowedKeys.contains(parts[2]) else {
            return .rejected("不允许的参数键：\(parts[2])")
        }
        guard isNonNegativeInteger(parts[3]) else {
            return .rejected("参数值必须是十进制非负整数，收到：\(parts[3])")
        }
        return .accepted([parts[1], parts[2], parts[3]])

    default:
        return .rejected("命令不在白名单内：\(command)")
    }
}

/// 只接受纯数字且不以符号开头的十进制非负整数（拒绝 `+1`、`-1`、`0x10`、`1 2` 等）。
private func isNonNegativeInteger(_ text: String) -> Bool {
    guard !text.isEmpty, text.count <= 18 else { return false }
    guard text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
    guard let value = Int(text), value >= 0 else { return false }
    return true
}

// MARK: - XPC Listener Delegate

final class HelperDelegate: NSObject, NSXPCListenerDelegate, HelperProtocol {

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // 安全验证：设置对端必须满足的代码签名 requirement。
        // 只有 identifier 为 local.pmset.app 的进程才能连接，
        // 防止其他进程通过 XPC 以 root 身份执行命令。
        // 系统在连接 resume 后自动验证，不满足则连接失败。
        newConnection.setCodeSigningRequirement(kAllowedCallerRequirement)

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func runCommands(_ commands: [String], reply: @escaping (Bool, String) -> Void) {
        // 先整批校验：任一条不合法就整批拒绝，且不执行任何一条。
        var argumentLists: [[String]] = []
        for command in commands {
            switch validate(command) {
            case .accepted(let arguments):
                argumentLists.append(arguments)
            case .rejected(let reason):
                reply(false, "命令被拒绝：\(reason)\n未执行任何命令。")
                return
            }
        }

        guard !argumentLists.isEmpty else {
            reply(false, "命令列表为空，未执行任何命令。")
            return
        }

        var combinedOutput = ""
        var overallSuccess = true

        for (command, arguments) in zip(commands, argumentLists) {
            let result = runPmset(arguments)
            combinedOutput += "$ \(command)\n\(result.output)"
            if result.status != 0 {
                overallSuccess = false
                combinedOutput += "[命令失败，退出码 \(result.status)]\n"
                break
            }
        }

        reply(overallSuccess, combinedOutput)
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(kHelperVersion)
    }

    // MARK: - Private

    /// 直接以参数数组执行 pmset，不经过 shell。
    private func runPmset(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: kPmsetPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return (1, "\(error.localizedDescription)\n")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

// MARK: - Main

// machServiceName 必须与 Helper 的 CFBundleIdentifier 完全一致。
let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "local.pmset.helper")
listener.delegate = delegate
listener.resume()

// Helper 由 launchd 拉起，常驻运行，通过 RunLoop 等待 XPC 连接。
RunLoop.main.run()
