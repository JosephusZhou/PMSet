import Foundation

/// 键所属的四个层级。抑制层决定「睡不睡」，其余三层决定「睡得有多深」。
enum PowerGroup: String, CaseIterable, Identifiable {
    case suppress
    case display
    case depth
    case network

    var id: String { rawValue }

    /// 分组标题，用于自定义配置窗口的分节。
    var title: String {
        switch self {
        case .suppress: return "抑制层"
        case .display: return "显示层"
        case .depth: return "电源层"
        case .network: return "网络层"
        }
    }

    /// 分组说明。
    var summary: String {
        switch self {
        case .suppress: return "决定系统会不会进入睡眠"
        case .display: return "决定屏幕与磁盘空闲多久后休眠"
        case .depth: return "决定睡眠时如何省电与断电"
        case .network: return "决定睡眠期间是否维持网络连接"
        }
    }
}

/// 取值形态，决定 UI 使用哪种编辑控件。
enum PowerValueKind {
    /// 非负整数，单位分钟，0 表示永不
    case minutes
    /// 0 / 1 开关
    case toggle
    /// 仅 0 / 3 / 25
    case hibernateMode
}

/// 单个 pmset 键的元数据。
///
/// 文案依据：docs/research/pmset键值组合与方案设计/report.md
/// 的「逐键语义」与「搭配关系」两节，未做额外推断。
struct PowerKey: Identifiable, Equatable {

    /// pmset 参数名（写入时使用）
    let key: String
    /// 中文名
    let title: String
    let group: PowerGroup
    let valueKind: PowerValueKind
    /// 单位 / 取值域说明
    let unitText: String
    /// 一句话说明：想「不睡」设什么、想「正常睡」设什么
    let shortDesc: String
    /// ⚠️ 风险提示；无风险为 nil
    let warning: String?
    /// 是否高风险键，UI 需突出提示
    let isHighRisk: Bool

    var id: String { key }

    /// 允许的取值；nil 表示任意非负整数。
    var allowedValues: [Int]? {
        switch valueKind {
        case .minutes: return nil
        case .toggle: return [0, 1]
        case .hibernateMode: return [0, 3, 25]
        }
    }

    /// 9 个键的元数据，按四层顺序排列。
    static let all: [PowerKey] = [
        PowerKey(
            key: "disablesleep",
            title: "禁止一切睡眠",
            group: .suppress,
            valueKind: .toggle,
            unitText: "开关",
            shortDesc: "想让电脑永远不睡请打开（合盖也不睡）；想正常睡眠请关闭。",
            warning: "全局禁止睡眠，合盖也保持运行；忘记关闭会持续发热耗电，请确保能随时切回默认方案",
            isHighRisk: true
        ),
        PowerKey(
            key: "sleep",
            title: "系统空闲睡眠",
            group: .suppress,
            valueKind: .minutes,
            unitText: "分钟",
            shortDesc: "想空闲后自动睡眠设分钟数（如 10）；想开盖永不空闲睡眠设 0（合盖仍会睡）。",
            warning: "开盖时也不会因空闲而睡眠",
            isHighRisk: true
        ),
        PowerKey(
            key: "displaysleep",
            title: "屏幕休眠计时",
            group: .display,
            valueKind: .minutes,
            unitText: "分钟",
            shortDesc: "想屏幕自动熄灭设分钟数（如 5）；想屏幕常亮设 0。",
            warning: "保持屏幕常亮时切忌合盖，否则会影响散热和大量耗电，加速屏幕老化",
            isHighRisk: true
        ),
        PowerKey(
            key: "disksleep",
            title: "磁盘休眠计时",
            group: .display,
            valueKind: .minutes,
            unitText: "分钟",
            shortDesc: "想磁盘空闲后休眠设分钟数；现代 Mac 用不到，保持默认即可。",
            warning: nil,
            isHighRisk: false
        ),
        PowerKey(
            key: "hibernatemode",
            title: "休眠模式",
            group: .depth,
            valueKind: .hibernateMode,
            unitText: "0 / 3 / 25",
            shortDesc: "想纯内存睡眠（断电丢数据）设 0；想断电后还能恢复会话设 3 或 25。",
            warning: "断电会丢失未保存数据，台式机默认值不代表笔记本安全",
            isHighRisk: true
        ),
        PowerKey(
            key: "standby",
            title: "深度待机",
            group: .depth,
            valueKind: .toggle,
            unitText: "开关",
            shortDesc: "想睡眠时更省电请打开；想不写镜像、唤醒更快请关闭。",
            warning: nil,
            isHighRisk: false
        ),
        PowerKey(
            key: "autopoweroff",
            title: "自动断电",
            group: .depth,
            valueKind: .toggle,
            unitText: "开关",
            shortDesc: "想插电睡眠后进入更低功耗请打开；保持现状请关闭。",
            warning: nil,
            isHighRisk: false
        ),
        PowerKey(
            key: "tcpkeepalive",
            title: "睡眠中维持 TCP",
            group: .network,
            valueKind: .toggle,
            unitText: "开关",
            shortDesc: "想睡眠中维持网络（「查找我的 Mac」可用）请打开；关闭会让这些功能失效。",
            warning: "会影响「查找我的 Mac」等依赖睡眠期网络的功能",
            isHighRisk: true
        ),
        PowerKey(
            key: "womp",
            title: "网络唤醒",
            group: .network,
            valueKind: .toggle,
            unitText: "开关",
            shortDesc: "想被网络请求唤醒请打开；不想被唤醒请关闭。",
            warning: nil,
            isHighRisk: false
        )
    ]

    /// 9 个键的参数名。
    static var allKeys: [String] { all.map(\.key) }

    /// 按参数名取元数据。
    static func info(for key: String) -> PowerKey? {
        all.first { $0.key == key }
    }
}
