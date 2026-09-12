import Foundation
import PMSetShared

/// Helper 的版本号，必须与 App 端 PrivilegedHelperManager.helperVersion 一致。
let kHelperVersion = "1.0.0"

/// 允许连接的调用者 requirement：必须是本 App（identifier 匹配）。
/// 通过 NSXPCConnection.setCodeSigningRequirement(_:) 设置，系统自动验证。
private let kAllowedCallerRequirement = "identifier \"local.pmset.app\""

// MARK: - XPC Listener Delegate

final class HelperDelegate: NSObject, NSXPCListenerDelegate, HelperProtocol {

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // 安全验证：设置对端必须满足的代码签名 requirement。
        // 只有 identifier 为 local.pmset.app 的进程才能连接，
        // 防止其他进程通过 XPC 以 root 身份执行任意命令。
        // 系统在连接 resume 后自动验证，不满足则连接失败。
        newConnection.setCodeSigningRequirement(kAllowedCallerRequirement)

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func runCommands(_ commands: [String], reply: @escaping (Bool, String) -> Void) {
        var combinedOutput = ""
        var overallSuccess = true

        for command in commands {
            let result = runShell(command)
            combinedOutput += "$ \(command)\n\(result.output)\n"
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

    private func runShell(_ command: String) -> (status: Int32, output: String) {
        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return (1, error.localizedDescription)
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
