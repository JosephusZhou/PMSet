import Foundation

/// 一套具名电源方案：9 个 pmset 键的一组取值。
struct Preset: Codable, Identifiable, Equatable {

    /// 内置「默认睡眠方案」的固定 id。
    static let builtinDefaultID = "builtin.default"
    /// 首次启动时预置的「合盖不睡眠方案」固定 id。
    static let seededLidClosedID = "builtin.lid-closed-no-sleep"
    /// 首次启动时预置的「开盖不睡眠方案」固定 id。
    static let seededLidOpenID = "builtin.lid-open-no-sleep"

    let id: String
    var name: String
    /// 参数名 → 取值；只保存本机存在的键，缺失的键表示沿用系统当前值。
    var values: [String: Int]
    /// 内置方案不可重命名 / 删除
    var isBuiltin: Bool
    var createdAt: Date
}
