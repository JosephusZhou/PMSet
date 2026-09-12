import AppKit
import Foundation

/// 电源配置管理：备份、恢复、合盖不睡眠切换。
///
/// 特权操作通过 AppleScript（`do shell script ... with administrator privileges`）
/// 执行，系统会弹出密码输入框，输入密码后以 root 身份执行。
/// 无需代码签名证书，ad-hoc 签名即可。
///
/// 注意：AppleScript 方式的授权框仅支持密码输入，不支持 Touch ID。
/// 若未来需要指纹授权或"授权一次、永久静默"，可切换到 SMJobBless 方案
/// （详见 PrivilegedHelperManager.swift 顶部预留说明）。
///
/// 多条 pmset 命令合并为一条 shell 命令（用 `;` 连接），因此每次操作只需输入一次密码。
final class PMSetManager {

    private let keys = [
        "disablesleep", "sleep", "standby", "autopoweroff",
        "hibernatemode", "tcpkeepalive", "womp", "displaysleep", "disksleep"
    ]

    private var backupURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PMSet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pmset-backup.txt")
    }

    // MARK: - 备份（只读，无需管理员权限）

    func backup() {
        let output = capture("/usr/bin/pmset", ["-g"]).output + "\n" + capture("/usr/bin/pmset", ["-g", "custom"]).output
        var lines: [String] = []
        for key in keys {
            if let value = value(for: key, in: output) {
                lines.append("\(key) \(value)")
            }
        }
        do {
            try lines.joined(separator: "\n").write(to: backupURL, atomically: true, encoding: .utf8)
            showInfo("备份完成", "已将 \(lines.count) 项电源配置保存到：\n\(backupURL.path)")
        } catch {
            showError("备份失败", error.localizedDescription)
        }
    }

    // MARK: - 恢复（需要管理员权限）

    func restore() {
        guard let content = try? String(contentsOf: backupURL, encoding: .utf8) else {
            showError("恢复失败", "未找到备份文件：\n\(backupURL.path)")
            return
        }
        var commands: [String] = []
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            // 安全校验：只允许已知的电源配置键，防止备份文件被篡改导致命令注入
            guard keys.contains(key) else { continue }
            // 值校验：pmset 的值均为非负整数
            guard let intValue = Int(value), intValue >= 0 else { continue }
            commands.append("/usr/bin/pmset -a \(key) \(intValue)")
        }
        guard !commands.isEmpty else {
            showError("恢复失败", "备份文件为空或格式不正确。")
            return
        }
        if runAsAdmin(commands.joined(separator: "; ")) {
            showInfo("恢复完成", "已按备份文件恢复 \(commands.count) 项电源配置。")
        }
    }

    // MARK: - 合盖不睡眠（需要管理员权限）

    func setLidNoSleep() {
        let command = [
            "/usr/bin/pmset -a disablesleep 1",
            "/usr/bin/pmset -a sleep 0",
            "/usr/bin/pmset -a standby 0",
            "/usr/bin/pmset -a autopoweroff 0",
            "/usr/bin/pmset -a hibernatemode 0",
            "/usr/bin/pmset -a displaysleep 0",
            "/usr/bin/pmset -a disksleep 0",
            "/usr/bin/pmset -a tcpkeepalive 1",
            "/usr/bin/pmset -a womp 1"
        ].joined(separator: "; ")

        if runAsAdmin(command) {
            showInfo(
                "已设置合盖不睡眠",
                "请插上电源适配器使用。无风扇机型长时间运行可能发热。\n\n需要恢复时选择「设置合盖睡眠（恢复默认）」或「恢复备份配置」。"
            )
        }
    }

    func setLidSleep() {
        let command = [
            "/usr/bin/pmset -a disablesleep 0",
            "/usr/bin/pmset -a sleep 1",
            "/usr/bin/pmset -a standby 1",
            "/usr/bin/pmset -a autopoweroff 1",
            "/usr/bin/pmset -a hibernatemode 3"
        ].joined(separator: "; ")

        if runAsAdmin(command) {
            showInfo("已恢复合盖睡眠", "电源设置已恢复为默认睡眠行为。")
        }
    }

    /// 当前是否为「合盖不睡眠」状态（只读，无需管理员权限）。
    func isLidNoSleepEnabled() -> Bool {
        let output = capture("/usr/bin/pmset", ["-g", "custom"]).output
        if value(for: "disablesleep", in: output) == "1" { return true }
        return value(for: "hibernatemode", in: output) == "0"
    }

    // MARK: - 管理员授权（AppleScript 方式）

    /// 通过 AppleScript 以管理员权限执行一条 shell 命令。
    /// 系统会弹出密码输入框，输入密码后执行。
    /// 注意：此授权框仅支持密码输入，不支持 Touch ID。
    /// - Parameter shellCommand: 要执行的 shell 命令（可包含多条，用 `;` 连接）。
    /// - Returns: 是否执行成功。
    @discardableResult
    private func runAsAdmin(_ shellCommand: String) -> Bool {
        // 转义命令中的反斜杠和双引号，确保嵌入 AppleScript 字符串后语法正确
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escaped)\" with administrator privileges with prompt \"PMSet 需要管理员权限来修改电源设置\""

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            showError("执行失败", "无法创建 AppleScript 实例。")
            return false
        }

        appleScript.executeAndReturnError(&error)

        if let error = error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "未知错误"
            // 用户取消授权时不弹错误提示
            if message.contains("User canceled") || message.contains("取消") {
                return false
            }
            showError("需要管理员权限", "未授权或命令执行失败：\n\(message)")
            return false
        }

        return true
    }

    // MARK: - 私有工具

    private func value(for key: String, in output: String) -> String? {
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count >= 2, parts[0] == key {
                return String(parts[1])
            }
        }
        return nil
    }

    private func capture(_ executable: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (1, "")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func showInfo(_ title: String, _ message: String) {
        showAlert(title, message, .informational)
    }

    private func showError(_ title: String, _ message: String) {
        showAlert(title, message, .warning)
    }

    private func showAlert(_ title: String, _ message: String, _ style: NSAlert.Style) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}
