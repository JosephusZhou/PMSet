import AppKit
import Foundation

/// 一次方案应用的结果。
struct ApplyReport {
    /// 实际下发并回读校验通过的键
    var appliedKeys: [String] = []
    /// 本机不存在而跳过的键
    var skippedKeys: [String] = []
    /// 失败键 → 失败原因
    var failedKeys: [String: String] = [:]
    /// 给用户看的中文摘要（可为空）
    var message: String = ""
    /// 是否已经弹过「合盖状态下不会立即入睡」的询问框（调用方据此避免再弹成功框）
    var promptedSleepNow: Bool = false

    var success: Bool { failedKeys.isEmpty }
}

/// 电源配置管理：备份、恢复、方案应用。
///
/// 所有特权写入统一走 `runPrivileged(_:completion:)`：优先使用 SMJobBless 特权 Helper
/// （授权一次后静默执行），Helper 不可用时自动回退 AppleScript 密码方式。
final class PMSetManager {

    /// 已知的 9 个电源配置键（参数名），用于备份、恢复与方案下发
    private let keys = PowerKey.allKeys

    private var backupURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PMSet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pmset-backup.txt")
    }

    // MARK: - 备份（只读，无需管理员权限）

    func backup() {
        // 备份写参数名：disablesleep 由 `pmset -g` 的 SleepDisabled 映射而来
        let snapshot = SystemPowerReader().snapshot()
        var lines: [String] = []
        for key in keys {
            if let value = snapshot.value(for: key) {
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
        runPrivileged(commands) { success, canceled, message in
            if success {
                self.showInfo("恢复完成", "已按备份文件恢复 \(commands.count) 项电源配置。")
            } else if !canceled {
                self.showError("恢复失败", message)
            }
        }
    }

    /// 当前是否禁止睡眠（只读，无需管理员权限）。以 `pmset -g` 的 SleepDisabled 为准。
    func isLidNoSleepEnabled() -> Bool {
        SystemPowerReader().snapshot().sleepDisabled
    }

    // MARK: - 方案应用

    /// 应用一套具名方案：只下发与当前实际值有差异的键，执行后回读校验；
    /// 全部成功时把该方案记为当前生效方案。
    func applyPreset(_ preset: Preset, completion: @escaping (ApplyReport) -> Void) {
        if preset.id == Preset.builtinDefaultID {
            applyBuiltinDefaultPreset(completion: completion)
            return
        }
        apply(values: preset.values, activatePresetID: preset.id, completion: completion)
    }

    /// 只把草稿值写入系统，不改动当前生效方案。
    func applyDraft(_ values: [String: Int], completion: @escaping (ApplyReport) -> Void) {
        apply(values: values, activatePresetID: nil, completion: completion)
    }

    /// 当前是否合盖（只读）。`ioreg` 中 `AppleClamshellState = Yes` 表示合盖。
    /// 注意：ioreg 位于 /usr/sbin，不在 /usr/bin。
    var isLidClosed: Bool {
        let output = CommandCapture
            .run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"])
            .output
        for line in output.split(separator: "\n") where line.contains("AppleClamshellState") {
            let value = line.split(separator: "=").last?
                .trimmingCharacters(in: .whitespaces) ?? ""
            return value.caseInsensitiveCompare("Yes") == .orderedSame
        }
        return false
    }

    // MARK: - 方案应用（内部实现）

    /// 差异下发 + 回读校验的公共流程。
    /// - Parameters:
    ///   - values: 目标键值（可以只包含部分键）
    ///   - activatePresetID: 成功后要记为当前生效方案的 id；nil 表示不改（草稿应用）
    private func apply(
        values: [String: Int],
        activatePresetID: String?,
        completion: @escaping (ApplyReport) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = SystemPowerReader().snapshot()

            var targets: [(key: String, value: Int)] = []
            var skipped: [String] = []
            for key in self.keys {
                guard let target = values[key] else { continue }
                // 本机不存在的键不下发，记录后跳过
                guard snapshot.isAvailable(key) else {
                    skipped.append(key)
                    continue
                }
                if !snapshot.matchesAllPowerModes(key, target: target) {
                    targets.append((key, target))
                }
            }

            // disablesleep 是系统级总开关，必须排在命令列表最后
            var ordered = targets.filter { $0.key != "disablesleep" }
            if let disableSleep = targets.first(where: { $0.key == "disablesleep" }) {
                ordered.append(disableSleep)
            }

            var base = ApplyReport()
            base.skippedKeys = skipped

            guard !ordered.isEmpty else {
                DispatchQueue.main.async {
                    var report = base
                    report.message = "当前已处于该方案状态，无需修改"
                    if let id = activatePresetID {
                        PresetStore.shared.setActive(id: id)
                    }
                    completion(report)
                }
                return
            }

            let commands = ordered.map { "/usr/bin/pmset -a \($0.key) \($0.value)" }
            // 本次是否把 disablesleep 从 1 改回 0：合盖时改回来不会立即入睡，需要额外提示
            let turnsOffDisableSleep = snapshot.value(for: "disablesleep") == 1
                && ordered.contains { $0.key == "disablesleep" && $0.value == 0 }

            self.runPrivileged(commands) { success, canceled, message in
                guard success else {
                    var report = base
                    let reason = canceled ? "用户取消了授权" : message
                    for target in ordered {
                        report.failedKeys[target.key] = "未写入"
                    }
                    report.message = "写入未执行：\(reason)"
                    completion(report)
                    return
                }
                self.verify(
                    targets: ordered,
                    skipped: skipped,
                    activatePresetID: activatePresetID,
                    promptSleepNow: turnsOffDisableSleep,
                    completion: completion
                )
            }
        }
    }

    /// 执行后回读，逐键比对目标值。
    private func verify(
        targets: [(key: String, value: Int)],
        skipped: [String],
        activatePresetID: String?,
        promptSleepNow: Bool,
        completion: @escaping (ApplyReport) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = SystemPowerReader().snapshot()
            // 只有本次确实关闭了 disablesleep 时才需要读合盖状态
            let lidClosed = promptSleepNow && self.isLidClosed

            var report = ApplyReport()
            report.skippedKeys = skipped
            for target in targets {
                if snapshot.matchesAllPowerModes(target.key, target: target.value) {
                    report.appliedKeys.append(target.key)
                } else {
                    report.failedKeys[target.key] = snapshot.mismatchDescription(for: target.key, target: target.value)
                }
            }
            report.message = self.summary(for: report)

            let needsSleepPrompt = lidClosed && report.appliedKeys.contains("disablesleep")

            DispatchQueue.main.async {
                if let id = activatePresetID, report.failedKeys.isEmpty {
                    PresetStore.shared.setActive(id: id)
                }
                guard needsSleepPrompt else {
                    completion(report)
                    return
                }
                self.promptSleepNowIfNeeded { sleptNow in
                    var finalReport = report
                    finalReport.promptedSleepNow = true
                    if sleptNow {
                        finalReport.message += "\n已执行立即睡眠。"
                    }
                    completion(finalReport)
                }
            }
        }
    }

    /// 默认睡眠方案：`pmset restoredefaults` 恢复电源档位默认，并显式把系统级 `disablesleep` 归 0。
    private func applyBuiltinDefaultPreset(completion: @escaping (ApplyReport) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let before = SystemPowerReader().snapshot()
            let turnsOffDisableSleep = before.value(for: "disablesleep") == 1

            // `pmset restoredefaults` 只恢复分电源配置，不会重置系统级的 SleepDisabled，
            // 必须显式追加 `disablesleep 0`（放在最后，与 apply() 顺序一致）。
            let commands = [
                "/usr/bin/pmset restoredefaults",
                "/usr/bin/pmset -a disablesleep 0"
            ]
            self.runPrivileged(commands) { success, canceled, message in
                guard success else {
                    var report = ApplyReport()
                    let reason = canceled ? "用户取消了授权" : message
                    report.failedKeys["restoredefaults"] = "未执行"
                    report.message = "恢复默认设置失败：\(reason)"
                    completion(report)
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    let snapshot = SystemPowerReader().snapshot()
                    let lidClosed = turnsOffDisableSleep && self.isLidClosed

                    let values = snapshot.defaultRecordingValues(for: self.keys)

                    var report = ApplyReport()
                    let actualDisableSleep = snapshot.value(for: "disablesleep")
                    if actualDisableSleep != 0 {
                        let actualText = actualDisableSleep.map(String.init) ?? "未知"
                        report.failedKeys["disablesleep"] = "实际值 \(actualText)"
                        report.message = "恢复默认设置未完全生效：disablesleep 仍为 \(actualText)"
                    } else {
                        report.appliedKeys = self.keys.filter { values[$0] != nil }
                        report.message = "已恢复系统默认电源设置，并记录当前值到默认睡眠方案。"
                    }

                    let needsSleepPrompt = lidClosed && report.failedKeys.isEmpty

                    DispatchQueue.main.async {
                        if report.failedKeys.isEmpty {
                            PresetStore.shared.update(id: Preset.builtinDefaultID, values: values)
                            PresetStore.shared.setActive(id: Preset.builtinDefaultID)
                        }
                        guard needsSleepPrompt else {
                            completion(report)
                            return
                        }
                        self.promptSleepNowIfNeeded { sleptNow in
                            var finalReport = report
                            finalReport.promptedSleepNow = true
                            if sleptNow {
                                finalReport.message += "\n已执行立即睡眠。"
                            }
                            completion(finalReport)
                        }
                    }
                }
            }
        }
    }

    /// 合盖状态下关掉 disablesleep 时的提示：可以顺手让 Mac 立即睡眠。
    /// 文案明确说明「合盖状态下改回允许睡眠不会立即入睡」。
    private func promptSleepNowIfNeeded(completion: @escaping (Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "已恢复允许睡眠"
        alert.informativeText = "当前处于合盖状态。合盖状态下改回允许睡眠不会立即入睡，需要的话可以现在就让 Mac 睡眠。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.addButton(withTitle: "立即睡眠")

        guard alert.runModal() == .alertSecondButtonReturn else {
            completion(false)
            return
        }
        runPrivileged(["/usr/bin/pmset sleepnow"]) { success, _, _ in
            completion(success)
        }
    }

    private func summary(for report: ApplyReport) -> String {
        var parts: [String] = []
        if !report.appliedKeys.isEmpty {
            parts.append("已修改 \(report.appliedKeys.count) 项：\(report.appliedKeys.joined(separator: "、"))")
        }
        if !report.skippedKeys.isEmpty {
            parts.append("本机不支持、已跳过：\(report.skippedKeys.joined(separator: "、"))")
        }
        if !report.failedKeys.isEmpty {
            let details = report.failedKeys
                .sorted { $0.key < $1.key }
                .map { "\($0.key)（\($0.value)）" }
                .joined(separator: "、")
            parts.append("以下键写入失败：\(details)")
        }
        if parts.isEmpty {
            parts.append("当前已处于该方案状态，无需修改")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - 特权执行（Helper 优先，失败回退 AppleScript）

    /// 统一的特权执行入口。
    ///
    /// 先尝试特权 Helper（授权一次后静默执行），失败则回退 AppleScript 密码方式；
    /// 两者都失败时只把错误信息回调给上层一次，不在这里弹窗。
    /// 回调固定回到主线程。
    private func runPrivileged(
        _ commands: [String],
        completion: @escaping (_ success: Bool, _ canceled: Bool, _ message: String) -> Void
    ) {
        PrivilegedHelperManager.shared.runCommands(commands) { success, canceled, output in
            if success {
                completion(true, false, output)
                return
            }
            if canceled {
                completion(false, true, output)
                return
            }
            NSLog("PMSet: helper 执行失败，回退 AppleScript：\(output)")

            // Helper 不可用（未安装 / 签名不符 / 版本不匹配 / XPC 失败）：回退密码方式，用 && 保持失败即停语义
            DispatchQueue.global(qos: .userInitiated).async {
                let fallback = PrivilegedHelperManager.executeAsAdminViaAppleScript(commands.joined(separator: " && "))
                DispatchQueue.main.async {
                    completion(fallback.success, fallback.canceled, fallback.success ? "" : fallback.message)
                }
            }
        }
    }

    // MARK: - 私有工具

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
