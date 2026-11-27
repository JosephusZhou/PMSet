import Foundation

/// 方案操作错误，`errorDescription` 可直接展示给用户。
enum PresetError: LocalizedError {
    case emptyName
    case duplicateName
    case limitReached(Int)
    case builtinReadOnly
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "方案名称不能为空"
        case .duplicateName:
            return "已存在同名方案"
        case .limitReached(let max):
            return "最多只能保存 \(max) 个自定义方案"
        case .builtinReadOnly:
            return "内置方案不可重命名或删除"
        case .notFound:
            return "方案不存在，可能已被删除"
        }
    }
}

/// 方案仓库：JSON 持久化于 ~/Library/Application Support/PMSet/presets.json。
///
/// 每次变更立即落盘；读取失败时用内置方案兜底，不覆盖原文件
/// （下次保存前会把原文件改名为 presets.json.bak 保留）。
final class PresetStore {

    static let shared = PresetStore()

    /// 自定义方案数量上限
    static let maxCustomCount = 10

    private static let schemaVersion = 1

    /// 内置方案种子版本：旧文件没有该字段，载入时补写两套内置方案。
    private static let seedVersion = 1

    /// 全部方案，内置方案始终在第一位，其余按用户顺序排列
    private(set) var presets: [Preset] = []
    /// 当前生效方案 id
    private(set) var activePresetID: String = Preset.builtinDefaultID

    /// 读取失败标记
    private var loadFailed = false

    private init() {
        load()
    }

    // MARK: - 查询

    /// 用户自定义方案，保持用户顺序
    var customPresets: [Preset] {
        presets.filter { !$0.isBuiltin }
    }

    /// 内置「默认睡眠方案」
    var builtinPreset: Preset {
        presets.first(where: { $0.id == Preset.builtinDefaultID }) ?? Self.makeBuiltin()
    }

    /// 当前生效方案
    var activePreset: Preset? {
        presets.first { $0.id == activePresetID }
    }

    func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    // MARK: - 增删改

    /// 校验方案名称（去首尾空白、非空、不重名），返回规范化后的名称。
    func validateName(_ name: String, excludingID: String? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresetError.emptyName }
        guard !presets.contains(where: { $0.id != excludingID && $0.name == trimmed }) else {
            throw PresetError.duplicateName
        }
        return trimmed
    }

    /// 校验是否允许新建自定义方案（名称合法且未超上限），返回规范化后的名称。
    func validateCanAdd(name: String) throws -> String {
        let trimmed = try validateName(name)
        guard customPresets.count < Self.maxCustomCount else {
            throw PresetError.limitReached(Self.maxCustomCount)
        }
        return trimmed
    }

    /// 新建自定义方案。
    @discardableResult
    func add(name: String, values: [String: Int]) throws -> Preset {
        let trimmed = try validateCanAdd(name: name)
        let preset = Preset(
            id: UUID().uuidString,
            name: trimmed,
            values: values,
            isBuiltin: false,
            createdAt: Date()
        )
        presets.append(preset)
        save()
        return preset
    }

    /// 重命名；默认方案拒绝。
    func rename(id: String, newName: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw PresetError.notFound }
        guard !presets[index].isBuiltin else { throw PresetError.builtinReadOnly }
        let trimmed = try validateName(newName, excludingID: id)
        presets[index].name = trimmed
        save()
    }

    /// 复制方案（内置方案也可复制成自定义方案）。
    @discardableResult
    func duplicate(id: String) throws -> Preset {
        guard let source = presets.first(where: { $0.id == id }) else { throw PresetError.notFound }
        guard customPresets.count < Self.maxCustomCount else {
            throw PresetError.limitReached(Self.maxCustomCount)
        }
        let preset = Preset(
            id: UUID().uuidString,
            name: uniqueCopyName(of: source.name),
            values: source.values,
            isBuiltin: false,
            createdAt: Date()
        )
        // 复制内置方案时放在内置方案之后，复制用户方案时追加到末尾
        if source.isBuiltin {
            presets.insert(preset, at: min(1, presets.count))
        } else {
            presets.append(preset)
        }
        save()
        return preset
    }

    /// 删除方案；默认方案拒绝，删除当前方案时回落到默认方案。
    func delete(id: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }), !presets[index].isBuiltin else {
            return
        }
        presets.remove(at: index)
        if activePresetID == id {
            activePresetID = Preset.builtinDefaultID
        }
        save()
    }

    /// 更新方案取值；内置方案也允许（用于 restoredefaults 后回写快照）。
    func update(id: String, values: [String: Int]) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].values = values
        save()
    }

    /// 设置当前生效方案。
    func setActive(id: String) {
        guard presets.contains(where: { $0.id == id }), activePresetID != id else { return }
        activePresetID = id
        save()
    }

    /// 按给定 id 顺序重排自定义方案（内置默认方案始终锁定在首位）。
    func reorderCustom(ids: [String]) {
        let customByID = Dictionary(uniqueKeysWithValues: customPresets.map { ($0.id, $0) })
        var seen = Set<String>()
        var reordered: [Preset] = []
        for id in ids where seen.insert(id).inserted {
            if let preset = customByID[id] {
                reordered.append(preset)
            }
        }
        let missing = customPresets.filter { !seen.contains($0.id) }
        let next = [builtinPreset] + reordered + missing
        guard next.map(\.id) != presets.map(\.id) else { return }
        presets = next
        save()
    }

    // MARK: - 持久化

    private struct StoreFile: Codable {
        var schemaVersion: Int
        /// 内置方案种子版本；旧文件没有该字段，视为 0。
        var seedVersion: Int?
        var activePresetID: String
        var presets: [Preset]
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PMSet", isDirectory: true)
    }

    private var fileURL: URL {
        Self.directoryURL.appendingPathComponent("presets.json")
    }

    private static func makeBuiltin() -> Preset {
        Preset(
            id: Preset.builtinDefaultID,
            name: "默认睡眠方案",
            values: [:],
            isBuiltin: true,
            createdAt: Date()
        )
    }

    /// 首次载入时预置的两套方案；之后与普通自定义方案完全一致。
    private static func makeSeededPresets() -> [Preset] {
        [
            Preset(
                id: Preset.seededLidClosedID,
                name: "合盖不睡眠方案",
                values: ["disablesleep": 1],
                isBuiltin: false,
                createdAt: Date()
            ),
            Preset(
                id: Preset.seededLidOpenID,
                name: "开盖不睡眠方案",
                values: ["disablesleep": 0, "sleep": 0, "displaysleep": 0],
                isBuiltin: false,
                createdAt: Date()
            )
        ]
    }

    /// 第一次启动时的完整方案列表。
    private static func makeInitialPresets() -> [Preset] {
        [makeBuiltin()] + makeSeededPresets()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // 首次启动：先落盘内置方案，保证文件存在
            presets = Self.makeInitialPresets()
            activePresetID = Preset.builtinDefaultID
            save()
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            // 文件存在但读不出来：兜底且不覆盖原文件
            loadFailed = true
            presets = Self.makeInitialPresets()
            activePresetID = Preset.builtinDefaultID
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(StoreFile.self, from: data) else {
            // 读取失败：空列表兜底，保留原文件不覆盖
            loadFailed = true
            presets = Self.makeInitialPresets()
            activePresetID = Preset.builtinDefaultID
            return
        }

        presets = file.presets
        ensureDefaultPreset()
        // activePresetID 必须指向存在的方案，否则回落到默认方案
        activePresetID = presets.contains(where: { $0.id == file.activePresetID })
            ? file.activePresetID
            : Preset.builtinDefaultID

        // 老版本没有种子版本号：补写两套预置方案并立即落盘；
        // 之后用户删除它们也不会再被补回（种子版本号已经写入文件）。
        let demoted = demoteSeededPresets()
        let seeded = seedPresetsIfNeeded(from: file.seedVersion ?? 0)
        if demoted || seeded {
            save()
        }
    }

    /// 保证默认方案存在且排在第一位。
    private func ensureDefaultPreset() {
        if let index = presets.firstIndex(where: { $0.id == Preset.builtinDefaultID }) {
            if index != 0 {
                let preset = presets.remove(at: index)
                presets.insert(preset, at: 0)
            }
        } else {
            presets.insert(Self.makeBuiltin(), at: 0)
        }
    }

    /// 预置方案曾短暂被标记为内置，统一降级为普通自定义方案；返回是否有改动。
    private func demoteSeededPresets() -> Bool {
        let ids: Set<String> = [Preset.seededLidClosedID, Preset.seededLidOpenID]
        var changed = false
        for index in presets.indices where ids.contains(presets[index].id) && presets[index].isBuiltin {
            presets[index].isBuiltin = false
            changed = true
        }
        return changed
    }

    /// 按种子版本补写缺失的预置方案；返回是否需要落盘。
    private func seedPresetsIfNeeded(from version: Int) -> Bool {
        guard version < Self.seedVersion else { return false }
        var insertIndex = 1
        for preset in Self.makeSeededPresets()
        where !presets.contains(where: { $0.id == preset.id }) {
            presets.insert(preset, at: min(insertIndex, presets.count))
            insertIndex += 1
        }
        return true
    }

    private func save() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)

        // 原文件读取失败时先改名保留，避免静默覆盖用户数据
        if loadFailed, fileManager.fileExists(atPath: fileURL.path) {
            let backupURL = fileURL.appendingPathExtension("bak")
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.moveItem(at: fileURL, to: backupURL)
            loadFailed = false
        }

        let file = StoreFile(
            schemaVersion: Self.schemaVersion,
            seedVersion: Self.seedVersion,
            activePresetID: activePresetID,
            presets: presets
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 「XXX 副本」，重名时依次追加序号。
    private func uniqueCopyName(of name: String) -> String {
        let base = "\(name) 副本"
        guard presets.contains(where: { $0.name == base }) else { return base }
        var index = 2
        while presets.contains(where: { $0.name == "\(base) \(index)" }) {
            index += 1
        }
        return "\(base) \(index)"
    }
}
