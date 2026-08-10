import AppKit
import Foundation

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

    // MARK: - 菜单动作

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

    func restore() {
        guard let content = try? String(contentsOf: backupURL, encoding: .utf8) else {
            showError("恢复失败", "未找到备份文件：\n\(backupURL.path)")
            return
        }
        var commands: [String] = []
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == 2 {
                commands.append("pmset -a \(parts[0]) \(parts[1])")
            }
        }
        guard !commands.isEmpty else {
            showError("恢复失败", "备份文件为空或格式不正确。")
            return
        }
        if runAsAdmin(commands.joined(separator: "; ")) {
            showInfo("恢复完成", "已按备份文件恢复 \(commands.count) 项电源配置。")
        }
    }

    func setLidNoSleep() {
        let command = [
            "pmset -a disablesleep 1",
            "pmset -a sleep 0",
            "pmset -a standby 0",
            "pmset -a autopoweroff 0",
            "pmset -a hibernatemode 0",
            "pmset -a displaysleep 0",
            "pmset -a disksleep 0",
            "pmset -a tcpkeepalive 1",
            "pmset -a womp 1"
        ].joined(separator: "; ")
        if runAsAdmin(command) {
            showInfo("已设置合盖不睡眠", "请插上电源适配器使用。无风扇机型长时间运行可能发热。\n\n需要恢复时选择「设置合盖睡眠（恢复默认）」或「恢复备份配置」。")
        }
    }

    func setLidSleep() {
        let command = [
            "pmset -a disablesleep 0",
            "pmset -a sleep 1",
            "pmset -a standby 1",
            "pmset -a autopoweroff 1",
            "pmset -a hibernatemode 3"
        ].joined(separator: "; ")
        if runAsAdmin(command) {
            showInfo("已恢复合盖睡眠", "电源设置已恢复为默认睡眠行为。")
        }
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

    @discardableResult
    private func runAsAdmin(_ shellCommand: String) -> Bool {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges with prompt \"PMSet 需要管理员权限来修改电源设置\""
        let result = capture("/usr/bin/osascript", ["-e", script])
        if result.status != 0 {
            let detail = result.output.isEmpty ? "" : "\n\(result.output)"
            showError("需要管理员权限", "未授权或命令执行失败（退出码 \(result.status)）。\(detail)")
        }
        return result.status == 0
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
