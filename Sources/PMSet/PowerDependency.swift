import Foundation

/// 键之间的依赖关系：某些键打开后，另一些键的设置不会生效。
///
/// 依据：docs/research/pmset键值组合与方案设计/report.md 的两条硬规则
///   - R3：`disablesleep 1` 时睡眠深度键与网络层键不会被触发（机器从不入睡）；
///   - R1：「完全不写休眠镜像」需要 hibernatemode / standby / autopoweroff 同时为 0。
///
/// 编辑界面据此把无效的选项置灰，并在用户点击时说明原因。
enum PowerDependency {

    /// 依赖规则：触发键取到指定值时，受影响键的设置不生效。
    struct Rule {
        let triggerKey: String
        let triggerValue: Int
        /// 受影响的键
        let affectedKeys: [String]
        /// 给用户看的解释
        let reason: String
    }

    /// `disablesleep 1` 时，深度层与网络层不生效。
    static let rules: [Rule] = [
        Rule(
            triggerKey: "disablesleep",
            triggerValue: 1,
            affectedKeys: ["hibernatemode", "standby", "autopoweroff", "tcpkeepalive", "womp"],
            reason: "「禁止一切睡眠」已开启，机器不会进入睡眠，这些设置当前不会生效。"
        )
    ]

    /// 根据草稿计算「被禁用」的键 → 禁用原因。
    static func blockedKeys(draft: [String: Int]) -> [String: String] {
        var result: [String: String] = [:]
        for rule in rules where (draft[rule.triggerKey] ?? 0) == rule.triggerValue {
            for key in rule.affectedKeys {
                result[key] = rule.reason
            }
        }
        return result
    }

    /// 不禁用、但需要提醒的组合：键 → 提示文案。
    ///
    /// R1 的推论：`hibernatemode 0` 只是「不主动写镜像」，只要 standby / autopoweroff 任一为 1，
    /// 系统仍可能在睡眠时写镜像，用户以为的「纯内存睡眠」就不成立。
    static func warnings(draft: [String: Int]) -> [String: String] {
        var result: [String: String] = [:]
        guard draft["hibernatemode"] == 0 else { return result }

        var causes: [String] = []
        if draft["standby"] == 1 { causes.append("深度待机") }
        if draft["autopoweroff"] == 1 { causes.append("自动断电") }
        guard !causes.isEmpty else { return result }

        let text = "「\(causes.joined(separator: "、"))」已打开，仍可能写入休眠镜像；要完全不写镜像需将其关闭。"
        result["hibernatemode"] = text
        return result
    }
}
