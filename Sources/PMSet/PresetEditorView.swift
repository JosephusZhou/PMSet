import AppKit

/// 方案编辑器视图：新建方案与查看 / 编辑方案复用同一界面。
///
/// 顶部是 52pt 标题栏（返回 + 名称），正文按「层级」分卡片展示 9 个选项，
/// 底部按钮按场景不同：
/// - 内置默认方案：只读，只能「以此新建方案」
/// - 自定义方案：可保存，可保存并应用，也可删除
/// - 新建方案：初始值取自默认方案
final class PresetEditorView: NSView {

    enum Mode {
        /// 查看内置默认方案（只读）
        case builtin
        /// 查看 / 编辑已有自定义方案
        case existing(Preset)
        /// 新建自定义方案
        case new
    }

    /// 返回方案列表
    var onBack: (() -> Void)?
    /// 方案仓库发生变化，需要刷新列表
    var onStoreChanged: (() -> Void)?
    /// 新方案已保存，需要回到列表
    var onPresetCreated: ((Preset) -> Void)?
    /// 从内置方案「以此新建方案」
    var onCreateFromBuiltin: (() -> Void)?

    private let manager = PMSetManager()

    private var mode: Mode = .new
    /// 草稿：pmset 键 → 取值；只存在于内存
    private var draft: [String: Int] = [:]
    /// 本机实际存在的键
    private var availableKeys: Set<String> = []
    private var isBusy = false
    /// 每次 load(_:) 递增，用于丢弃切页前未完成的异步回调对当前 UI 的操作
    private var loadGeneration = 0

    // MARK: - 控件

    private let headerBar = DSHeaderBar(showsBack: true, showsPlus: false)
    private let scrollView = NSScrollView()
    private let pageTitleLabel = DS.label("", size: 28, weight: .bold, color: DS.text)
    private let pageBadge = DSPaddedLabel(
        text: "内置 · 只读",
        font: DS.font(12, .semibold),
        textColor: DS.accentText,
        background: DS.accentFaint,
        cornerRadius: 6,
        insets: NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8),
        symbol: "lock.fill",
        symbolSize: 11
    )
    private let pageSubtitleLabel = DS.wrappingLabel("", size: 13, color: DS.secondaryText)
    private let nameCard = DSCardView()
    private let nameField = DSInputField(width: 360)
    private let footerBar = NSView()
    private let footerNote = NSStackView()
    private let statusLabel = DS.label("", size: 12, color: DS.secondaryText)
    private let footerButtons = NSStackView()

    private var rows: [String: PresetOptionRow] = [:]
    private var saveButton: DSButton?
    private var applyButton: DSButton?
    private var deleteButton: DSButton?

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = DS.canvas.cgColor

        headerBar.onBack = { [weak self] in self?.onBack?() }

        buildNameCard()

        // 正文滚动区
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let document = DSFlippedStackView(frame: .zero)
        document.orientation = .vertical
        document.alignment = .leading
        document.spacing = 22
        document.edgeInsets = NSEdgeInsets(top: 24, left: 0, bottom: 28, right: 0)
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        let pageHeader = makePageHeader()
        document.addArrangedSubview(pageHeader)
        pageHeader.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true

        document.addArrangedSubview(nameCard)
        nameCard.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true

        for group in PowerGroup.allCases {
            let section = makeSection(for: group)
            document.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true
        }

        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor)
        ])

        buildFooter()

        addSubview(headerBar)
        addSubview(scrollView)
        addSubview(footerBar)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),

            footerBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makePageHeader() -> NSView {
        let titleRow = NSStackView(views: [pageTitleLabel, pageBadge, DS.spacer()])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        pageBadge.isHidden = true

        let header = NSStackView(views: [titleRow, pageSubtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 6
        header.translatesAutoresizingMaskIntoConstraints = false
        for subview in header.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        }
        return header
    }

    private func buildNameCard() {
        nameCard.translatesAutoresizingMaskIntoConstraints = false

        let caption = DS.label("方案名称", size: 13.5, weight: .medium, color: DS.text)
        let row = NSStackView(views: [caption, DS.spacer(), nameField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false

        nameCard.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: nameCard.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: nameCard.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: nameCard.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: nameCard.bottomAnchor, constant: -10)
        ])
    }

    /// 一个层级：标题 + 说明 +（可选）橙色横幅 + 卡片内的选项行。
    private func makeSection(for group: PowerGroup) -> NSView {
        let title = DS.label(group.title, size: 15, weight: .semibold, color: DS.text)
        let summary = DS.label(group.summary, size: 12, color: DS.secondaryText)
        let headerStack = NSStackView(views: [title, summary])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        for subview in headerStack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
        }

        let headerContainer = NSView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 4),
            headerStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -4),
            headerStack.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            headerStack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor)
        ])

        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        section.translatesAutoresizingMaskIntoConstraints = false
        section.addArrangedSubview(headerContainer)
        headerContainer.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        if group == .depth {
            let banner = DSWarningBanner(text: "断电会丢失未保存数据，台式机默认值不代表笔记本安全。")
            section.addArrangedSubview(banner)
            banner.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }

        let card = DSCardView()
        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        // 裁齐卡片圆角，避免首尾行的禁用蒙版盖出卡片外缘，同时保留 card 外阴影
        rowsStack.wantsLayer = true
        rowsStack.layer?.cornerRadius = 12
        rowsStack.layer?.masksToBounds = true

        let groupKeys = PowerKey.all.filter { $0.group == group }
        for (index, info) in groupKeys.enumerated() {
            if index > 0 {
                let divider = DS.divider()
                rowsStack.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            }
            let row = PresetOptionRow(info: info)
            row.onChange = { [weak self] key, value in self?.handleChange(key: key, value: value) }
            row.onBlockedClick = { [weak self] anchor, reason in self?.showTip(anchor: anchor, text: reason) }
            rows[info.key] = row
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }

        card.addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: card.topAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        section.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func buildFooter() {
        footerBar.translatesAutoresizingMaskIntoConstraints = false
        footerBar.wantsLayer = true
        footerBar.layer?.backgroundColor = DS.canvas.cgColor

        let topLine = DS.divider(color: DS.barSeparator)
        footerBar.addSubview(topLine)

        let lock = NSImageView()
        lock.translatesAutoresizingMaskIntoConstraints = false
        lock.image = DS.symbol("lock.fill", pointSize: 14, weight: .regular)
        lock.contentTintColor = DS.secondaryText
        lock.widthAnchor.constraint(equalToConstant: 14).isActive = true
        lock.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let noteLabel = DS.label("内置方案不可修改，也不能保存应用。", size: 12.5, color: DS.secondaryText)
        footerNote.orientation = .horizontal
        footerNote.alignment = .centerY
        footerNote.spacing = 8
        footerNote.translatesAutoresizingMaskIntoConstraints = false
        footerNote.addArrangedSubview(lock)
        footerNote.addArrangedSubview(noteLabel)

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let leftStack = NSStackView(views: [footerNote, statusLabel])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 12
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        footerButtons.orientation = .horizontal
        footerButtons.alignment = .centerY
        footerButtons.spacing = 10
        footerButtons.translatesAutoresizingMaskIntoConstraints = false

        footerBar.addSubview(topLine)
        footerBar.addSubview(leftStack)
        footerBar.addSubview(footerButtons)

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: footerBar.topAnchor),

            footerButtons.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -28),
            footerButtons.topAnchor.constraint(equalTo: footerBar.topAnchor, constant: 12),
            footerButtons.bottomAnchor.constraint(equalTo: footerBar.bottomAnchor, constant: -12),

            leftStack.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 28),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: footerButtons.leadingAnchor, constant: -16),
            leftStack.centerYAnchor.constraint(equalTo: footerButtons.centerYAnchor)
        ])
    }

    // MARK: - 载入场景

    /// 载入一个场景：重置草稿、标题与底部按钮。
    func load(_ newMode: Mode) {
        loadGeneration += 1
        isBusy = false
        mode = newMode
        let snapshot = SystemPowerReader().snapshot()
        availableKeys = snapshot.availableKeys
        let systemValues = snapshot.values.filter { PowerKey.allKeys.contains($0.key) }

        let title: String
        let subtitle: String
        switch newMode {
        case .builtin:
            let preset = PresetStore.shared.builtinPreset
            draft = preset.values.isEmpty ? systemValues : preset.values
            title = preset.name
            subtitle = "内置方案，仅供查看：不能修改，也不能保存应用。切换方案请用菜单栏。"
        case .existing(let preset):
            draft = preset.values
            title = preset.name
            subtitle = "自定义方案：可以修改数值，保存后可选是否应用到系统。"
        case .new:
            let builtin = PresetStore.shared.builtinPreset
            draft = builtin.values.isEmpty ? systemValues : builtin.values
            title = "新建方案"
            subtitle = "初始数值取自「\(builtin.name)」，修改后可保存为新的自定义方案。"
        }

        headerBar.setTitle(title)
        pageTitleLabel.stringValue = title
        pageSubtitleLabel.stringValue = subtitle
        pageBadge.isHidden = !isBuiltin
        nameCard.isHidden = isBuiltin
        nameField.stringValue = currentName

        statusLabel.stringValue = ""
        statusLabel.textColor = DS.secondaryText

        for (key, row) in rows {
            row.setValue(draft[key])
        }

        rebuildFooter()
        refreshStates()

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private var isBuiltin: Bool {
        if case .builtin = mode { return true }
        return false
    }

    /// 当前方案名称：新建时给一个不重名的建议名。
    private var currentName: String {
        switch mode {
        case .builtin:
            return PresetStore.shared.builtinPreset.name
        case .existing(let preset):
            return preset.name
        case .new:
            let base = "我的方案"
            var name = base
            var index = 2
            while PresetStore.shared.presets.contains(where: { $0.name == name }) {
                name = "\(base) \(index)"
                index += 1
            }
            return name
        }
    }

    // MARK: - 底部按钮

    private func rebuildFooter() {
        for view in footerButtons.arrangedSubviews {
            footerButtons.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        saveButton = nil
        applyButton = nil
        deleteButton = nil

        footerNote.isHidden = !isBuiltin

        switch mode {
        case .builtin:
            let createButton = DSButton(
                title: "以此新建方案",
                style: .secondary,
                target: self,
                action: #selector(createFromBuiltin)
            )
            footerButtons.addArrangedSubview(createButton)
            saveButton = createButton
        case .existing:
            let delete = DSButton(
                title: "删除方案",
                style: .secondary,
                textColor: DS.danger,
                target: self,
                action: #selector(deletePreset)
            )
            let save = DSButton(
                title: "仅保存",
                style: .secondary,
                target: self,
                action: #selector(saveOnly)
            )
            let apply = DSButton(
                title: "保存并应用",
                style: .primary,
                target: self,
                action: #selector(applyAndSave)
            )
            footerButtons.addArrangedSubview(delete)
            footerButtons.addArrangedSubview(save)
            footerButtons.addArrangedSubview(apply)
            deleteButton = delete
            saveButton = save
            applyButton = apply
        case .new:
            let save = DSButton(
                title: "保存为方案",
                style: .secondary,
                target: self,
                action: #selector(saveOnly)
            )
            let apply = DSButton(
                title: "保存并应用",
                style: .primary,
                target: self,
                action: #selector(applyAndSave)
            )
            footerButtons.addArrangedSubview(save)
            footerButtons.addArrangedSubview(apply)
            saveButton = save
            applyButton = apply
        }
        updateActionAvailability()
    }

    // MARK: - 状态刷新

    /// 重新计算每个选项的可编辑状态（依赖禁写、本机不支持、内置只读）。
    private func refreshStates() {
        let blocked = PowerDependency.blockedKeys(draft: draft)
        let dynamic = PowerDependency.warnings(draft: draft)

        for (key, row) in rows {
            var reason = blocked[key]
            if reason == nil, isBuiltin {
                reason = "内置方案不可修改。"
            }
            row.refreshState(
                available: availableKeys.contains(key),
                blockedReason: reason,
                readOnly: isBuiltin,
                warning: dynamic[key]
            )
        }
        updateActionAvailability()
    }

    private func updateActionAvailability() {
        saveButton?.isEnabled = !isBusy
        applyButton?.isEnabled = !isBusy
        deleteButton?.isEnabled = !isBusy
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        updateActionAvailability()
    }

    private func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? DS.danger : DS.secondaryText
        statusLabel.toolTip = text
    }

    // MARK: - 动作

    private func handleChange(key: String, value: Int?) {
        if let value {
            draft[key] = value
        } else {
            draft.removeValue(forKey: key)
        }
        refreshStates()
    }

    @objc private func createFromBuiltin() {
        onCreateFromBuiltin?()
    }

    // MARK: - 保存

    /// 校验所有可编辑的分钟输入：留空表示沿用系统，非空时必须是非负整数。
    private func validateDraft() -> Bool {
        for (key, row) in rows {
            guard row.info.valueKind == .minutes, row.isControlEditable else { continue }
            guard row.isMinutesInputValid else {
                setStatus("「\(row.info.title)」需填写非负整数（分钟），0 表示永不", isError: true)
                return false
            }
            if let value = row.currentIntValue {
                draft[key] = value
            } else {
                draft.removeValue(forKey: key)
            }
        }
        return true
    }

    /// 仅保存到方案仓库，不写系统。
    @objc private func saveOnly() {
        guard validateDraft() else { return }
        switch mode {
        case .builtin:
            return
        case .existing(let preset):
            do {
                let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if name != preset.name {
                    try PresetStore.shared.rename(id: preset.id, newName: name)
                }
                PresetStore.shared.update(id: preset.id, values: draft)
                syncModeWithStore(id: preset.id)
                NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                onStoreChanged?()
                setStatus("已保存方案「\(name)」")
            } catch {
                setStatus((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, isError: true)
            }
        case .new:
            do {
                let preset = try PresetStore.shared.add(
                    name: nameField.stringValue,
                    values: draft
                )
                NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                onStoreChanged?()
                onPresetCreated?(preset)
            } catch {
                setStatus((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, isError: true)
            }
        }
    }

    /// 保存并写入系统。
    @objc private func applyAndSave() {
        guard validateDraft() else { return }

        switch mode {
        case .builtin:
            return
        case .existing(let preset):
            let validatedName: String
            do {
                validatedName = try PresetStore.shared.validateName(nameField.stringValue, excludingID: preset.id)
            } catch {
                setStatus((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, isError: true)
                return
            }

            let generation = loadGeneration
            let appliedDraft = draft
            setBusy(true)
            setStatus("正在写入系统…")

            var target = preset
            target.values = appliedDraft
            manager.applyPreset(target) { report in
                let isCurrentPage = (self.loadGeneration == generation)
                guard report.failedKeys.isEmpty else {
                    if !report.appliedKeys.isEmpty {
                        NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                    }
                    guard isCurrentPage else { return }
                    self.setBusy(false)
                    self.setStatus(self.failureText(report), isError: true)
                    return
                }
                do {
                    if let current = PresetStore.shared.preset(id: preset.id) {
                        if validatedName != current.name {
                            try PresetStore.shared.rename(id: preset.id, newName: validatedName)
                        }
                        PresetStore.shared.update(id: preset.id, values: appliedDraft)
                    }
                } catch {
                    NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                    guard isCurrentPage else { return }
                    self.setBusy(false)
                    self.setStatus("已应用，但保存方案失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)", isError: true)
                    return
                }
                NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                self.onStoreChanged?()
                guard isCurrentPage else { return }
                self.setBusy(false)
                self.syncModeWithStore(id: preset.id)
                self.setStatus(self.successText(report))
            }
        case .new:
            let validatedName: String
            do {
                validatedName = try PresetStore.shared.validateCanAdd(name: nameField.stringValue)
            } catch {
                setStatus((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, isError: true)
                return
            }

            let generation = loadGeneration
            let appliedDraft = draft
            setBusy(true)
            setStatus("正在写入系统…")

            manager.applyDraft(appliedDraft) { report in
                let isCurrentPage = (self.loadGeneration == generation)
                guard report.failedKeys.isEmpty else {
                    if !report.appliedKeys.isEmpty {
                        NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                    }
                    guard isCurrentPage else { return }
                    self.setBusy(false)
                    self.setStatus(self.failureText(report), isError: true)
                    return
                }
                let created: Preset
                do {
                    created = try PresetStore.shared.add(
                        name: validatedName,
                        values: appliedDraft
                    )
                    PresetStore.shared.setActive(id: created.id)
                } catch {
                    NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                    guard isCurrentPage else { return }
                    self.setBusy(false)
                    self.setStatus("已应用，但保存方案失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)", isError: true)
                    return
                }
                NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                self.onStoreChanged?()
                guard isCurrentPage else { return }
                self.setBusy(false)
                self.onPresetCreated?(created)
            }
        }
    }

    /// 保存后让 mode 里的 Preset 与仓库同步，同时刷新标题。
    private func syncModeWithStore(id: String) {
        guard let updated = PresetStore.shared.preset(id: id) else { return }
        mode = .existing(updated)
        headerBar.setTitle(updated.name)
        pageTitleLabel.stringValue = updated.name
    }

    private func successText(_ report: ApplyReport) -> String {
        guard !report.appliedKeys.isEmpty else {
            return "当前已处于该方案状态，无需修改"
        }
        var text = "已保存并应用 \(report.appliedKeys.count) 项：\(report.appliedKeys.joined(separator: "、"))"
        if !report.skippedKeys.isEmpty {
            text += "；本机不支持、已跳过：\(report.skippedKeys.joined(separator: "、"))"
        }
        return text
    }

    private func failureText(_ report: ApplyReport) -> String {
        let lines = report.failedKeys
            .sorted { $0.key < $1.key }
            .map { "\($0.key)：\($0.value)" }
            .joined(separator: "；")
        var text = "以下键写入失败（草稿已保留）：\(lines)"
        if !report.message.isEmpty {
            text += "；\(report.message)"
        }
        return text
    }

    /// 删除当前自定义方案。
    @objc private func deletePreset() {
        guard case .existing(let preset) = mode else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除方案「\(preset.name)」？"
        alert.informativeText = "删除后无法恢复，系统当前的电源配置不会被修改。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        PresetStore.shared.delete(id: preset.id)
        NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
        onStoreChanged?()
        onBack?()
    }

    // MARK: - 提示气泡

    /// 在被置灰的控件旁弹出「为什么不生效」的说明。
    private func showTip(anchor: NSView, text: String) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = DSTipViewController(text: text)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
}

// MARK: - 选项行

/// 单个选项行：左侧标题 / 键名 / 说明 / 警告，右侧数值控件。
///
/// 被依赖关系禁用时整体置灰，并用一层透明视图接住点击、弹出原因说明。
final class PresetOptionRow: NSView {

    let info: PowerKey

    /// 数值变化回调（nil 表示沿用系统当前值）
    var onChange: ((String, Int?) -> Void)?
    /// 点击被置灰的控件时回调（锚点视图、原因）
    var onBlockedClick: ((NSView, String) -> Void)?

    /// 控件当前是否可编辑
    private(set) var isControlEditable = false

    /// 当前分钟输入的取值（留空或非法输入返回 nil）。
    var currentIntValue: Int? {
        minutesControl?.currentValue
    }

    /// 分钟输入是否合法（留空或非负整数均为合法）。
    var isMinutesInputValid: Bool {
        minutesControl?.isValidInput ?? true
    }

    private let leftColumn = NSStackView()
    private let controlHolder = NSView()
    private let blocker = DSBlockerView()
    private let disabledOverlay = DSPassThroughView()

    private let warningStack = NSStackView()
    private let warningLabel = DS.wrappingLabel("", size: 12, color: DS.warningText)
    private let unavailableStack = NSStackView()

    private let minutesControl: DSMinutesControl?
    private let toggle: DSToggleView?
    private let unsetToggleLabel: NSTextField?
    private let popup: NSPopUpButton?

    private var blockedReason: String?
    private var dynamicWarning: String?

    init(info: PowerKey) {
        self.info = info
        switch info.valueKind {
        case .minutes:
            self.minutesControl = DSMinutesControl()
            self.toggle = nil
            self.unsetToggleLabel = nil
            self.popup = nil
        case .toggle:
            self.minutesControl = nil
            self.toggle = DSToggleView()
            self.unsetToggleLabel = DS.label("沿用系统", size: 12, color: DS.secondaryText)
            self.popup = nil
        case .hibernateMode:
            self.minutesControl = nil
            self.toggle = nil
            self.unsetToggleLabel = nil
            self.popup = NSPopUpButton(frame: .zero, pullsDown: false)
        }
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = DS.label(info.title, size: 13.5, weight: .medium, color: DS.text)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let keyChip = DSPaddedLabel(
            text: info.key,
            font: DS.mono(11),
            textColor: DS.secondaryText,
            background: NSColor.black.withAlphaComponent(0.05),
            cornerRadius: 4,
            insets: NSEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
        )

        let titleRow = NSStackView(views: [titleLabel, keyChip, DS.spacer()])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = DS.wrappingLabel(info.shortDesc, size: 12, color: DS.secondaryText)

        let warningIcon = NSImageView()
        warningIcon.translatesAutoresizingMaskIntoConstraints = false
        warningIcon.image = DS.symbol("exclamationmark.triangle", pointSize: 14, weight: .regular)
        warningIcon.contentTintColor = DS.warningIcon
        warningIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        warningIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        warningStack.orientation = .horizontal
        warningStack.alignment = .top
        warningStack.spacing = 6
        warningStack.translatesAutoresizingMaskIntoConstraints = false
        warningStack.addArrangedSubview(warningIcon)
        warningStack.addArrangedSubview(warningLabel)
        warningLabel.widthAnchor.constraint(equalTo: warningStack.widthAnchor, constant: -20).isActive = true

        let unavailableIcon = NSImageView()
        unavailableIcon.translatesAutoresizingMaskIntoConstraints = false
        unavailableIcon.image = DS.symbol("nosign", pointSize: 13, weight: .semibold)
        unavailableIcon.contentTintColor = DS.danger
        unavailableIcon.widthAnchor.constraint(equalToConstant: 13).isActive = true
        unavailableIcon.heightAnchor.constraint(equalToConstant: 13).isActive = true

        let unavailableLabel = DS.label("本机不支持该设置", size: 12, color: DS.danger)
        unavailableStack.orientation = .horizontal
        unavailableStack.alignment = .centerY
        unavailableStack.spacing = 6
        unavailableStack.translatesAutoresizingMaskIntoConstraints = false
        unavailableStack.addArrangedSubview(unavailableIcon)
        unavailableStack.addArrangedSubview(unavailableLabel)
        unavailableLabel.widthAnchor.constraint(equalTo: unavailableStack.widthAnchor, constant: -19).isActive = true
        unavailableStack.isHidden = true

        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 3
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.setContentHuggingPriority(.init(1), for: .horizontal)
        leftColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftColumn.addArrangedSubview(titleRow)
        leftColumn.addArrangedSubview(descLabel)
        leftColumn.addArrangedSubview(warningStack)
        leftColumn.addArrangedSubview(unavailableStack)
        for subview in leftColumn.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: leftColumn.widthAnchor).isActive = true
        }

        let control = makeControl()
        controlHolder.translatesAutoresizingMaskIntoConstraints = false
        controlHolder.setContentHuggingPriority(.required, for: .horizontal)
        controlHolder.setContentCompressionResistancePriority(.required, for: .horizontal)
        controlHolder.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: controlHolder.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: controlHolder.trailingAnchor),
            control.topAnchor.constraint(equalTo: controlHolder.topAnchor),
            control.bottomAnchor.constraint(equalTo: controlHolder.bottomAnchor)
        ])

        blocker.translatesAutoresizingMaskIntoConstraints = false
        blocker.onClick = { [weak self] in
            guard let self, let reason = self.blockedReason else { return }
            self.onBlockedClick?(self.controlHolder, reason)
        }
        blocker.isHidden = true
        controlHolder.addSubview(blocker)
        NSLayoutConstraint.activate([
            blocker.leadingAnchor.constraint(equalTo: controlHolder.leadingAnchor),
            blocker.trailingAnchor.constraint(equalTo: controlHolder.trailingAnchor),
            blocker.topAnchor.constraint(equalTo: controlHolder.topAnchor),
            blocker.bottomAnchor.constraint(equalTo: controlHolder.bottomAnchor)
        ])

        disabledOverlay.translatesAutoresizingMaskIntoConstraints = false
        disabledOverlay.wantsLayer = true
        disabledOverlay.layer?.backgroundColor = DS.disabledOverlay.cgColor
        disabledOverlay.isHidden = true

        addSubview(leftColumn)
        addSubview(controlHolder)
        addSubview(disabledOverlay)
        NSLayoutConstraint.activate([
            leftColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            leftColumn.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            leftColumn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            controlHolder.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 24),
            controlHolder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            controlHolder.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlHolder.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
            controlHolder.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),

            disabledOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            disabledOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            disabledOverlay.topAnchor.constraint(equalTo: topAnchor),
            disabledOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applyWarning()
    }

    private func makeControl() -> NSView {
        switch info.valueKind {
        case .minutes:
            let control = minutesControl!
            control.onValueChange = { [weak self] value in
                guard let self else { return }
                self.applyWarning()
                self.onChange?(self.info.key, value)
            }
            return control
        case .toggle:
            let control = toggle!
            let unsetLabel = unsetToggleLabel!
            control.onChange = { [weak self] on in
                guard let self else { return }
                unsetLabel.isHidden = (on != nil)
                self.applyWarning()
                self.onChange?(self.info.key, on.map { $0 ? 1 : 0 })
            }
            let stack = NSStackView(views: [unsetLabel, control])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            return stack
        case .hibernateMode:
            let control = popup!
            control.translatesAutoresizingMaskIntoConstraints = false
            control.font = DS.font(13)
            control.bezelStyle = .rounded
            control.menu?.addItem(NSMenuItem(title: "沿用系统（不修改）", action: nil, keyEquivalent: ""))
            let options: [(Int, String)] = [
                (0, "0 纯内存睡眠"),
                (3, "3 安全睡眠（写镜像）"),
                (25, "25 休眠（断电保内存）")
            ]
            for (value, text) in options {
                let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                item.representedObject = value
                control.menu?.addItem(item)
            }
            control.target = self
            control.action = #selector(hibernateChanged(_:))
            control.widthAnchor.constraint(equalToConstant: 190).isActive = true
            return control
        }
    }

    // MARK: - 状态

    /// 写入数值（只在载入场景时调用）。
    func setValue(_ value: Int?) {
        minutesControl?.setValue(value)
        toggle?.state = value.map { $0 == 1 }
        unsetToggleLabel?.isHidden = (value != nil)
        if let popup {
            if let value,
               let item = popup.itemArray.first(where: { ($0.representedObject as? Int) == value }) {
                popup.select(item)
            } else {
                popup.selectItem(at: 0)
            }
        }
        applyWarning()
    }

    /// 刷新可编辑状态与提示文案（不改数值，避免打断正在输入的用户）。
    func refreshState(
        available: Bool,
        blockedReason: String?,
        readOnly: Bool,
        warning: String?
    ) {
        self.blockedReason = blockedReason
        self.dynamicWarning = warning
        isControlEditable = available && blockedReason == nil && !readOnly

        minutesControl?.readOnly = readOnly
        minutesControl?.isEditable = isControlEditable
        toggle?.isEnabled = isControlEditable
        popup?.isEnabled = isControlEditable

        let showOverlay = !available || (!readOnly && blockedReason != nil)
        disabledOverlay.isHidden = !showOverlay
        if showOverlay {
            controlHolder.alphaValue = 1
        } else if readOnly {
            controlHolder.alphaValue = info.valueKind == .minutes ? 1 : 0.55
        } else {
            controlHolder.alphaValue = 1
        }

        blocker.isHidden = blockedReason == nil
        unavailableStack.isHidden = available
        applyWarning()
    }

    /// 按当前取值决定显示哪条警告（设计稿里警告是条件出现的）。
    private func applyWarning() {
        var text: String?

        if let dynamicWarning {
            text = dynamicWarning
        } else if let warning = info.warning, let value = currentValue {
            switch info.key {
            case "disablesleep":
                if value == 1 { text = warning }
            case "sleep", "displaysleep", "tcpkeepalive":
                if value == 0 { text = warning }
            default:
                break
            }
        }

        warningLabel.stringValue = text ?? ""
        warningStack.isHidden = text == nil
    }

    private var currentValue: Int? {
        if let minutesControl { return minutesControl.currentValue }
        if let toggle { return toggle.state.map { $0 ? 1 : 0 } }
        if let popup { return popup.selectedItem?.representedObject as? Int }
        return nil
    }

    @objc private func hibernateChanged(_ sender: NSPopUpButton) {
        let value = sender.selectedItem?.representedObject as? Int
        applyWarning()
        onChange?(info.key, value)
    }
}

/// 仅做视觉遮罩、不拦截鼠标事件，确保下层 `DSBlockerView` 仍可响应点击弹气泡。
private final class DSPassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
