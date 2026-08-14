import AppKit
import Foundation

final class PMSetManager {

    private let skipTouchIDPromptKey = "PMSSkipTouchIDPrompt"

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

    /// 当前是否为「合盖不睡眠」状态（hibernatemode=0 或 disablesleep=1）
    func isLidNoSleepEnabled() -> Bool {
        let output = capture("/usr/bin/pmset", ["-g", "custom"]).output
        if value(for: "disablesleep", in: output) == "1" { return true }
        return value(for: "hibernatemode", in: output) == "0"
    }

    // MARK: - 管理员授权

    /// 是否已配置 Touch ID 指纹授权（/etc/pam.d 中存在未被注释的 pam_tid.so）
    private func pamTidConfigured() -> Bool {
        let paths = ["/etc/pam.d/sudo_local", "/etc/pam.d/sudo"]
        for path in paths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("auth"), trimmed.contains("pam_tid.so") {
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    private func runAsAdmin(_ shellCommand: String) -> Bool {
        if pamTidConfigured() {
            return runViaSudo(shellCommand)
        }
        if UserDefaults.standard.bool(forKey: skipTouchIDPromptKey) {
            return runViaOsaScript(shellCommand)
        }
        switch askTouchIDChoice() {
        case .configureTouchID:
            if runViaOsaScript(enableTouchIDScript) {
                showInfo("指纹授权已启用", "Touch ID 指纹授权配置完成（原配置已备份到 /etc/pam.d/*.pmset.bak）。后续管理员操作可直接使用指纹。")
                return runViaSudo(shellCommand)
            }
            showError("配置失败", "无法写入 /etc/pam.d 认证配置，本次已退回密码授权。")
            return runViaOsaScript(shellCommand)
        case .usePassword:
            return runViaOsaScript(shellCommand)
        }
    }

    /// 直接通过 sudo 提权执行（依赖 pam_tid 弹出指纹/密码授权框）
    private func runViaSudo(_ shellCommand: String) -> Bool {
        let result = capture("/usr/bin/sudo", ["-k", "/bin/sh", "-c", shellCommand])
        if result.status != 0 {
            let detail = result.output.isEmpty ? "" : "\n\(result.output)"
            showError("需要管理员权限", "未授权或命令执行失败（退出码 \(result.status)）。\(detail)")
        }
        return result.status == 0
    }

    /// 通过 osascript 弹系统密码授权框（未配置指纹时的回退方式）
    @discardableResult
    private func runViaOsaScript(_ shellCommand: String) -> Bool {
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

    /// 一次性配置 pam_tid（需先用密码授权一次写入 /etc/pam.d）
    private var enableTouchIDScript: String {
        """
        if grep -q "pam_tid" /etc/pam.d/sudo_local 2>/dev/null; then
            exit 0
        fi
        if grep -E -q "include[[:space:]]+sudo_local" /etc/pam.d/sudo 2>/dev/null; then
            if [ -f /etc/pam.d/sudo_local ]; then
                cp -p /etc/pam.d/sudo_local /etc/pam.d/sudo_local.pmset.bak
            fi
            echo '# sudo_local: local config file which survives system update and is included for sudo' > /etc/pam.d/sudo_local
            echo '# uncomment following line to enable Touch ID for sudo' >> /etc/pam.d/sudo_local
            echo 'auth       sufficient     pam_tid.so' >> /etc/pam.d/sudo_local
        else
            cp -p /etc/pam.d/sudo /etc/pam.d/sudo.pmset.bak
            echo 'auth       sufficient     pam_tid.so' > /var/tmp/pmset-sudo.new
            cat /etc/pam.d/sudo >> /var/tmp/pmset-sudo.new
            cat /var/tmp/pmset-sudo.new > /etc/pam.d/sudo
            rm -f /var/tmp/pmset-sudo.new
        fi
        """
    }

    private enum TouchIDChoice {
        case configureTouchID
        case usePassword
    }

    private func askTouchIDChoice() -> TouchIDChoice {
        if Thread.isMainThread {
            return touchIDAlert()
        }
        var choice: TouchIDChoice = .usePassword
        DispatchQueue.main.sync {
            choice = touchIDAlert()
        }
        return choice
    }

    private func touchIDAlert() -> TouchIDChoice {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "是否启用 Touch ID 指纹授权？"
        alert.informativeText = """
        当前系统未启用「Touch ID 指纹授权」。启用后，管理员操作会弹出指纹提示，按一下指纹即可授权，无需输入密码。

        风险与说明：
        • 将修改系统认证文件 /etc/pam.d/（配置前自动备份，可恢复）
        • 启用后，本机已录入的指纹均可直接获得管理员权限
        • 开机后首次解锁、连续 5 次指纹失败等情况下，系统仍会要求输入密码
        • 该配置对本机所有需要 sudo 权限的软件生效

        如不启用，所有管理员操作将退回「输入密码」方式。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "启用指纹授权")
        let declineButton = alert.addButton(withTitle: "不用，继续输密码")
        declineButton.keyEquivalent = "\u{1b}"
        let remember = NSButton(checkboxWithTitle: "记住我的选择，以后不再询问", target: nil, action: nil)
        alert.accessoryView = remember
        let response = alert.runModal()
        if remember.state == .on {
            UserDefaults.standard.set(true, forKey: skipTouchIDPromptKey)
        }
        return response == .alertFirstButtonReturn ? .configureTouchID : .usePassword
    }

    /// 菜单手动启用入口（可在已选择「以后不再询问」后恢复指纹授权）
    func enableTouchID() {
        if pamTidConfigured() {
            showInfo("已启用", "本机已配置 Touch ID 指纹授权，无需重复操作。")
            return
        }
        if askTouchIDChoice() == .configureTouchID {
            if runViaOsaScript(enableTouchIDScript) {
                showInfo("指纹授权已启用", "Touch ID 指纹授权配置完成（原配置已备份到 /etc/pam.d/*.pmset.bak）。")
            } else {
                showError("配置失败", "无法写入 /etc/pam.d 认证配置。\n\n可手动在终端执行：\nsudo pico /etc/pam.d/sudo_local\n并添加：auth sufficient pam_tid.so")
            }
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
