import Foundation

/// 一次电源状态读取的结果。
struct PowerSnapshot {
    /// 参数名 → 当前生效值（仅包含能解析为非负整数的键；`SleepDisabled` 已映射为 `disablesleep`）
    let values: [String: Int]
    /// `pmset -g custom` 各电源段（如 "AC Power"、"Battery Power"）的原始键值
    let sectionValues: [String: [String: Int]]
    /// 本机实际存在的键集合（`pmset -g cap` ∪ `pmset -g custom` ∪ 实际能回读到的已知键）
    let availableKeys: Set<String>
    /// 是否禁止一切睡眠（取自 `pmset -g` 的 `SleepDisabled`，不再用 hibernatemode 推断）
    var sleepDisabled: Bool

    func value(for key: String) -> Int? {
        values[key]
    }

    func isAvailable(_ key: String) -> Bool {
        availableKeys.contains(key)
    }

    /// 检查所有存在该键的电源档位（以及当前生效值）是否均等于目标值。
    /// 本 App 统一通过 `pmset -a` 下发，不能只看当前正在使用的那一侧电源。
    func matchesAllPowerModes(_ key: String, target: Int) -> Bool {
        let sectionHits = sectionValues.values.compactMap { $0[key] }
        if sectionHits.isEmpty {
            return values[key] == target
        }
        let currentMatches = values[key] == nil || values[key] == target
        return currentMatches && sectionHits.allSatisfy { $0 == target }
    }

    /// 当 `matchesAllPowerModes` 返回 false 时，给出准确的实际值说明。
    func mismatchDescription(for key: String, target: Int) -> String {
        if let current = values[key], current != target {
            return "实际值 \(current)"
        }
        for (section, dict) in sectionValues.sorted(by: { $0.key < $1.key }) {
            if let value = dict[key], value != target {
                return "\(section) 实际值 \(value)"
            }
        }
        return "实际值 \(values[key].map(String.init) ?? "未知")"
    }

    /// 供「默认睡眠方案」记录固定快照：优先取 AC 段（含电池以外的完整默认键），再补齐全局键。
    func defaultRecordingValues(for keys: [String]) -> [String: Int] {
        let preferred = sectionValues["AC Power"] ?? sectionValues["Battery Power"] ?? [:]
        var result: [String: Int] = [:]
        for key in keys {
            if let value = preferred[key] ?? values[key] {
                result[key] = value
            }
        }
        return result
    }

    /// 判定当前是否仍符合内置默认方案：全局 `disablesleep` 必须匹配，分电源键需匹配任一电源段或当前生效值。
    func matchesBuiltinDefault(comparable: [String: Int]) -> Bool {
        if let expectedDisableSleep = comparable["disablesleep"],
           values["disablesleep"] != expectedDisableSleep {
            return false
        }
        let scoped = comparable.filter { $0.key != "disablesleep" }
        guard !scoped.isEmpty else { return true }
        if scoped.allSatisfy({ values[$0.key] == $0.value }) {
            return true
        }
        return sectionValues.values.contains { section in
            scoped.allSatisfy { section[$0.key] == $0.value }
        }
    }
}

/// 读取层：解析 `pmset -g` / `pmset -g custom` / `pmset -g cap`，得到实际值与可用键集合。
struct SystemPowerReader {

    /// 读取当前电源状态（只读，不需要管理员权限）。
    func snapshot() -> PowerSnapshot {
        let globalResult = CommandCapture.run("/usr/bin/pmset", ["-g"])
        let global = parse(globalResult.output)
        let custom = parse(CommandCapture.run("/usr/bin/pmset", ["-g", "custom"]).output)
        let capabilities = parse(CommandCapture.run("/usr/bin/pmset", ["-g", "cap"]).output)

        // 分电源的键优先取 AC 段（本 App 统一按 -a 下发）；没有 AC 段时用电池段兜底。
        var values: [String: Int] = [:]
        if let ac = custom.sectionValues["AC Power"] {
            values = ac
        } else if let battery = custom.sectionValues["Battery Power"] {
            values = battery
        }
        // 最后用 `pmset -g` 的「Currently in use」覆盖，它才是当前真正生效的值。
        values.merge(global.values) { _, current in current }
        // 从未写入过 disablesleep 的机器上 `pmset -g` 不输出 SleepDisabled，语义等同 0。
        if globalResult.status == 0, values["disablesleep"] == nil {
            values["disablesleep"] = 0
        }

        var available = Set<String>()
        for keys in capabilities.sectionKeys.values { available.formUnion(keys) }
        for keys in custom.sectionKeys.values { available.formUnion(keys) }
        // `disablesleep` 只出现在 `pmset -g` 且 key 名不同，需按「实际能回读到的已知键」补入。
        available.formUnion(PowerKey.allKeys.filter { values[$0] != nil })

        return PowerSnapshot(
            values: values,
            sectionValues: custom.sectionValues,
            availableKeys: available,
            sleepDisabled: (values["disablesleep"] ?? 0) != 0
        )
    }

    // MARK: - 解析

    /// 一段 pmset 文本输出的解析结果。
    private struct ParsedOutput {
        /// 全局合并后的值
        var values: [String: Int] = [:]
        /// 分段值，如 "AC Power" → [key: value]
        var sectionValues: [String: [String: Int]] = [:]
        /// 分段出现的键（`-g cap` 的键只有名字没有值）
        var sectionKeys: [String: Set<String>] = [:]
    }

    /// 解析 pmset 输出：标题行（以 `:` 结尾）切换当前分段，数据行为「键 值」或仅有键名。
    private func parse(_ text: String) -> ParsedOutput {
        var result = ParsedOutput()
        var section = ""
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasSuffix(":") {
                section = String(line.dropLast())
                continue
            }
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard let first = parts.first else { continue }
            let key = parameterKey(for: String(first))
            if parts.count == 1 {
                // 能力列表里只有键名
                result.sectionKeys[section, default: []].insert(key)
                continue
            }
            guard let value = Int(parts[1]) else { continue }
            result.sectionKeys[section, default: []].insert(key)
            result.values[key] = value
            result.sectionValues[section, default: [:]][key] = value
        }
        return result
    }

    /// pmset 输出键名 → 参数名。`SleepDisabled` 是系统级开关，写入时叫 `disablesleep`。
    private func parameterKey(for outputKey: String) -> String {
        if outputKey.caseInsensitiveCompare("SleepDisabled") == .orderedSame {
            return "disablesleep"
        }
        return outputKey
    }
}

/// 外部命令调用（只读用途），与 PMSetManager 共享同一套进程调用方式。
enum CommandCapture {

    /// 执行命令并返回退出码与合并后的标准输出 / 标准错误文本。
    @discardableResult
    static func run(_ executable: String, _ args: [String]) -> (status: Int32, output: String) {
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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
