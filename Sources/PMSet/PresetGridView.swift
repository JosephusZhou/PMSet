import AppKit

/// 方案列表：网格展示「默认方案 + 自定义方案」，最后一个格子是「+」（新建方案）。
///
/// 点击方块进入查看 / 编辑界面；右键自定义方案可重命名、复制、删除。
final class PresetGridView: NSView {

    /// 选中一个已有方案
    var onSelect: ((Preset) -> Void)?
    /// 点击「+」新建方案
    var onCreate: (() -> Void)?

    private let headerBar = DSHeaderBar(showsBack: false, showsPlus: true)
    private let scrollView = NSScrollView()
    private let gridStack = NSStackView()

    private var customTiles: [DSPresetTileView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildContent()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = DS.canvas.cgColor

        headerBar.onPlus = { [weak self] in self?.onCreate?() }

        let title = DS.label("睡眠方案", size: 28, weight: .bold, color: DS.text)
        let subtitle = DS.wrappingLabel(
            "点击可查看、编辑，长按拖动可排序，右键可快捷操作。",
            size: 13,
            color: DS.secondaryText
        )
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pageHeader = NSStackView(views: [title, subtitle])
        pageHeader.orientation = .vertical
        pageHeader.alignment = .leading
        pageHeader.spacing = 6
        pageHeader.translatesAutoresizingMaskIntoConstraints = false
        for subview in pageHeader.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: pageHeader.widthAnchor).isActive = true
        }

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
        document.edgeInsets = NSEdgeInsets(top: 28, left: 0, bottom: 28, right: 0)
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        document.addArrangedSubview(pageHeader)
        pageHeader.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true

        gridStack.orientation = .vertical
        gridStack.alignment = .leading
        gridStack.spacing = 16
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        document.addArrangedSubview(gridStack)
        gridStack.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true

        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor)
        ])

        let footerView = makeFooter()

        addSubview(headerBar)
        addSubview(scrollView)
        addSubview(footerView)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),

            footerView.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let topLine = DS.divider(color: DS.barSeparator)
        footer.addSubview(topLine)

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = DS.symbol("info.circle", pointSize: 14, weight: .regular)
        icon.contentTintColor = DS.secondaryText
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let label = DS.label(
            "可通过右键或者系统菜单栏快捷切换方案。",
            size: 12.5,
            color: DS.secondaryText
        )

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(stack)

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: footer.topAnchor),

            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: footer.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -14)
        ])
        return footer
    }

    // MARK: - 重新加载

    /// 按仓库里的方案重建网格。
    func reload() {
        for row in gridStack.arrangedSubviews {
            gridStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        let builtin = makeTile(for: PresetStore.shared.builtinPreset)
        let customs = PresetStore.shared.customPresets.map { makeTile(for: $0) }
        let create = makeCreateTile()
        customTiles = customs

        var tiles: [NSView] = [builtin]
        tiles.append(contentsOf: customs)
        tiles.append(create)

        var index = 0
        while index < tiles.count {
            let end = min(index + 3, tiles.count)
            var rowViews = Array(tiles[index..<end])
            index = end
            while rowViews.count < 3 {
                let filler = NSView()
                filler.translatesAutoresizingMaskIntoConstraints = false
                rowViews.append(filler)
            }

            let row = NSStackView(views: rowViews)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = 16
            row.translatesAutoresizingMaskIntoConstraints = false
            gridStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: gridStack.widthAnchor).isActive = true
        }
    }

    // MARK: - 点击与长按拖动排序

    /// 用 window.trackEvents 统一处理「按下并抬起点击」和「长按拖动排序」。
    /// 拖动期间不拆装 NSStackView，只用 CALayer.transform 动画平移方块，避免卡顿与丢失 mouseUp。
    private func handleTileMouseDown(tile: DSPresetTileView, preset: Preset, downEvent: NSEvent) {
        guard let window else { return }

        let canDrag = !preset.isBuiltin && customTiles.count > 1
        let downLocation = downEvent.locationInWindow
        var lastLocation = downLocation
        var shouldStartDrag = false
        var canceledLongPress = false
        var didRelease = false
        var releasedInside = false

        let longPressDuration: TimeInterval = 0.25
        let deadline = Date().addingTimeInterval(longPressDuration)

        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: canDrag ? longPressDuration : NSEvent.foreverDuration,
            mode: .eventTracking
        ) { event, stop in
            guard let event else {
                if canDrag && !canceledLongPress {
                    shouldStartDrag = true
                }
                stop.pointee = true
                return
            }

            lastLocation = event.locationInWindow
            switch event.type {
            case .leftMouseUp:
                didRelease = true
                releasedInside = tile.bounds.contains(tile.convert(event.locationInWindow, from: nil))
                stop.pointee = true
            case .leftMouseDragged:
                if canDrag && !canceledLongPress {
                    let dx = event.locationInWindow.x - downLocation.x
                    let dy = event.locationInWindow.y - downLocation.y
                    if hypot(dx, dy) > 8 {
                        canceledLongPress = true
                    } else if Date() >= deadline {
                        shouldStartDrag = true
                        stop.pointee = true
                    }
                }
            default:
                break
            }
        }

        // 长按已取消但尚未松手：继续等 mouseUp，防止遗漏松手事件
        if !shouldStartDrag && !didRelease {
            window.trackEvents(
                matching: [.leftMouseDragged, .leftMouseUp],
                timeout: NSEvent.foreverDuration,
                mode: .eventTracking
            ) { event, stop in
                guard let event else {
                    stop.pointee = true
                    return
                }
                if event.type == .leftMouseUp {
                    releasedInside = tile.bounds.contains(tile.convert(event.locationInWindow, from: nil))
                    stop.pointee = true
                }
            }
        }

        guard shouldStartDrag else {
            if releasedInside {
                onSelect?(preset)
            }
            return
        }

        runDragSession(tile: tile, startLocation: lastLocation, in: window)
    }

    private func runDragSession(tile: DSPresetTileView, startLocation: NSPoint, in window: NSWindow) {
        guard let document = scrollView.documentView,
              customTiles.contains(where: { $0 === tile }) else { return }

        // 槽位固定在 document（翻转坐标系，Y 向下）中，滚动后坐标依然准确
        let initialTiles = customTiles
        let slotFramesInDoc = initialTiles.map { document.convert($0.bounds, from: $0) }
        var originIndexByID: [String: Int] = [:]
        for (idx, t) in initialTiles.enumerated() {
            originIndexByID[t.presetID] = idx
        }
        var currentTiles = initialTiles

        let startInSelf = convert(startLocation, from: nil)
        let tileFrameInSelf = tile.convert(tile.bounds, to: self)
        let grabOffset = NSPoint(
            x: startInSelf.x - tileFrameInSelf.origin.x,
            y: startInSelf.y - tileFrameInSelf.origin.y
        )

        let ghost = makeDragGhost(from: tile, frame: tileFrameInSelf)
        addSubview(ghost)
        tile.alphaValue = 0.22
        NSCursor.closedHand.push()

        var committed = true

        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { event, stop in
            guard let event else {
                committed = false
                stop.pointee = true
                return
            }

            switch event.type {
            case .leftMouseDragged:
                let pointInSelf = self.convert(event.locationInWindow, from: nil)
                ghost.frame.origin = NSPoint(
                    x: pointInSelf.x - grabOffset.x,
                    y: pointInSelf.y - grabOffset.y
                )

                // 仅在内容超出可视高度且拖到边缘时滚动，避免常规拖动每帧触发布局
                if document.bounds.height > self.scrollView.contentView.bounds.height {
                    let pointInScroll = self.scrollView.convert(event.locationInWindow, from: nil)
                    if pointInScroll.y < 36 || pointInScroll.y > self.scrollView.bounds.height - 36 {
                        let pointInDoc = document.convert(event.locationInWindow, from: nil)
                        document.scrollToVisible(
                            NSRect(x: pointInDoc.x - 10, y: pointInDoc.y - 36, width: 20, height: 72)
                        )
                    }
                }

                // 只检测自定义方案槽位：默认睡眠方案与末尾「+」天然不可移动
                let ghostCenterInSelf = NSPoint(x: ghost.frame.midX, y: ghost.frame.midY)
                let ghostCenterInDoc = document.convert(ghostCenterInSelf, from: self)
                guard let currentIndex = currentTiles.firstIndex(where: { $0 === tile }),
                      let targetIndex = slotFramesInDoc.firstIndex(where: { $0.contains(ghostCenterInDoc) }),
                      targetIndex != currentIndex else { return }

                let moved = currentTiles.remove(at: currentIndex)
                currentTiles.insert(moved, at: targetIndex)
                self.animateTiles(
                    currentTiles,
                    originIndexByID: originIndexByID,
                    slotFramesInDoc: slotFramesInDoc
                )

            case .leftMouseUp:
                committed = true
                stop.pointee = true

            case .keyDown where event.keyCode == 53:
                committed = false
                stop.pointee = true

            default:
                break
            }
        }

        ghost.removeFromSuperview()
        NSCursor.pop()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for t in initialTiles {
            t.layer?.removeAnimation(forKey: "reorderTransform")
            t.layer?.transform = CATransform3DIdentity
        }
        CATransaction.commit()
        tile.alphaValue = 1
        tile.resetHoverAppearance()

        let finalOrder = currentTiles.map(\.presetID)
        let initialOrder = initialTiles.map(\.presetID)
        if committed && finalOrder != initialOrder {
            PresetStore.shared.reorderCustom(ids: finalOrder)
            reload()
            NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
        }
    }

    private func animateTiles(
        _ orderedTiles: [DSPresetTileView],
        originIndexByID: [String: Int],
        slotFramesInDoc: [NSRect]
    ) {
        for (newIndex, t) in orderedTiles.enumerated() {
            guard let originIndex = originIndexByID[t.presetID],
                  let layer = t.layer else { continue }
            let dx = slotFramesInDoc[newIndex].origin.x - slotFramesInDoc[originIndex].origin.x
            let dyDown = slotFramesInDoc[newIndex].origin.y - slotFramesInDoc[originIndex].origin.y
            let dy = (layer.superlayer?.isGeometryFlipped ?? false) ? dyDown : -dyDown
            let target = CATransform3DMakeTranslation(dx, dy, 0)
            guard !CATransform3DEqualToTransform(layer.transform, target) else { continue }

            let current = layer.presentation()?.transform ?? layer.transform
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = NSValue(caTransform3D: current)
            anim.toValue = NSValue(caTransform3D: target)
            anim.duration = 0.18
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.transform = target
            layer.add(anim, forKey: "reorderTransform")
        }
    }

    private func makeDragGhost(from tile: DSPresetTileView, frame: NSRect) -> NSImageView {
        let image = NSImage(size: tile.bounds.size)
        if let rep = tile.bitmapImageRepForCachingDisplay(in: tile.bounds) {
            tile.cacheDisplay(in: tile.bounds, to: rep)
            image.addRepresentation(rep)
        }
        let ghost = NSImageView(frame: frame)
        ghost.image = image
        ghost.imageScaling = .scaleAxesIndependently
        ghost.wantsLayer = true
        ghost.layer?.cornerRadius = 12
        ghost.layer?.borderWidth = 1.5
        ghost.layer?.borderColor = DS.accent.withAlphaComponent(0.6).cgColor
        ghost.layer?.shadowColor = NSColor.black.cgColor
        ghost.layer?.shadowOpacity = 0.22
        ghost.layer?.shadowRadius = 10
        ghost.layer?.shadowOffset = CGSize(width: 0, height: -5)
        ghost.alphaValue = 0.96
        return ghost
    }

    // MARK: - 方块

    private func makeTile(for preset: Preset) -> DSPresetTileView {
        let tile = DSPresetTileView(
            presetID: preset.id,
            name: preset.name,
            summary: summaryText(values: preset.values),
            isBuiltin: preset.isBuiltin
        )
        tile.onMouseDown = { [weak self] view, event in
            self?.handleTileMouseDown(tile: view, preset: preset, downEvent: event)
        }
        tile.menu = makeMenu(for: preset)
        return tile
    }

    private func makeCreateTile() -> DSNewPresetTileView {
        let tile = DSNewPresetTileView()
        tile.onClick = { [weak self] in self?.onCreate?() }
        return tile
    }

    /// 方块上的一行摘要：只展示最关键的两三项。
    private func summaryText(values: [String: Int]) -> String {
        var parts: [String] = []
        if (values["disablesleep"] ?? 0) == 1 {
            parts.append("禁止一切睡眠")
        } else if let sleep = values["sleep"] {
            parts.append(sleep == 0 ? "空闲不睡" : "空闲 \(sleep) 分钟睡")
        }
        if let display = values["displaysleep"] {
            parts.append(display == 0 ? "屏幕常亮" : "屏幕 \(display) 分钟灭")
        }
        return parts.isEmpty ? "沿用系统当前值" : parts.joined(separator: " · ")
    }

    // MARK: - 右键菜单

    private func makeMenu(for preset: Preset) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("应用", #selector(applyPreset(_:)), preset.id))
        if !preset.isBuiltin {
            menu.addItem(.separator())
            menu.addItem(menuItem("重命名", #selector(renamePreset(_:)), preset.id))
            menu.addItem(menuItem("复制", #selector(duplicatePreset(_:)), preset.id))
            menu.addItem(menuItem("删除", #selector(deletePreset(_:)), preset.id))
        }
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector, _ presetID: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = presetID
        return item
    }

    /// 交给 AppDelegate 统一应用（复用菜单栏的 Helper / 密码回退与结果提示）。
    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        NotificationCenter.default.post(
            name: .presetApplyRequested,
            object: nil,
            userInfo: ["id": id]
        )
    }

    @objc private func renamePreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = PresetStore.shared.preset(id: id) else { return }
        var initialName = preset.name
        var errorText: String?

        while true {
            let alert = NSAlert()
            alert.alertStyle = errorText == nil ? .informational : .warning
            alert.messageText = errorText == nil ? "重命名方案" : "重命名失败"
            alert.informativeText = errorText ?? "输入新的方案名称。"
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.stringValue = initialName
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            initialName = field.stringValue

            do {
                try PresetStore.shared.rename(id: preset.id, newName: initialName)
                reload()
                NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
                return
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    @objc private func duplicatePreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        do {
            _ = try PresetStore.shared.duplicate(id: id)
            reload()
            NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "复制失败"
            alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func deletePreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = PresetStore.shared.preset(id: id) else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除方案「\(preset.name)」？"
        alert.informativeText = "删除后无法恢复，系统当前的电源配置不会被修改。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        PresetStore.shared.delete(id: preset.id)
        reload()
        NotificationCenter.default.post(name: .presetStoreDidChange, object: nil)
    }
}

// MARK: - 方案方块

/// 网格中的一个方案方块：图标 + 徽标、名称、摘要。
private final class DSPresetTileView: NSView {

    let presetID: String
    var onMouseDown: ((DSPresetTileView, NSEvent) -> Void)?

    init(presetID: String, name: String, summary: String, isBuiltin: Bool) {
        self.presetID = presetID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        heightAnchor.constraint(equalToConstant: 136).isActive = true

        wantsLayer = true
        layer?.backgroundColor = DS.card.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = DS.cardBorder.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 1
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        let icon = makeIcon(isBuiltin: isBuiltin)
        let badge: NSView
        if isBuiltin {
            badge = DSPaddedLabel(
                text: "内置",
                font: DS.font(11, .semibold),
                textColor: DS.accentText,
                background: DS.accentFaint,
                cornerRadius: 6,
                symbol: "lock.fill",
                symbolSize: 10
            )
        } else {
            badge = DSPaddedLabel(
                text: "自定义",
                font: DS.font(11, .semibold),
                textColor: DS.secondaryText,
                background: NSColor.black.withAlphaComponent(0.06),
                cornerRadius: 6
            )
        }

        let topRow = NSStackView(views: [icon, DS.spacer(), badge])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = DS.label(name, size: 15, weight: .semibold, color: DS.text)
        nameLabel.lineBreakMode = .byTruncatingTail

        let summaryLabel = DS.label(summary, size: 12, color: DS.secondaryText)
        summaryLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [nameLabel, summaryLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        for subview in textStack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        }

        let content = NSStackView(views: [topRow, textStack])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            topRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            textStack.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])

        updateTrackingAreas()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeIcon(isBuiltin: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = (isBuiltin ? DS.builtinIcon : DS.customIcon).cgColor
        container.layer?.cornerRadius = 9
        container.widthAnchor.constraint(equalToConstant: 36).isActive = true
        container.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = DS.symbol("moon.fill", pointSize: 19, weight: .regular)
        imageView.contentTintColor = .white
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        onMouseDown?(self, event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        layer?.shadowOpacity = 0.09
    }

    override func mouseExited(with event: NSEvent) {
        resetHoverAppearance()
    }

    func resetHoverAppearance() {
        layer?.borderColor = DS.cardBorder.cgColor
        layer?.shadowOpacity = 0.06
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - 新建方案方块

/// 网格末尾的「+」方块：虚线边框 + 圆形加号。
private final class DSNewPresetTileView: NSView {

    var onClick: (() -> Void)?

    private var isHovering = false
    private var isPressed = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        heightAnchor.constraint(equalToConstant: 136).isActive = true
        wantsLayer = true

        let circle = NSView()
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.wantsLayer = true
        circle.layer?.backgroundColor = DS.accentFaint.cgColor
        circle.layer?.cornerRadius = 16
        circle.widthAnchor.constraint(equalToConstant: 32).isActive = true
        circle.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let plus = NSImageView()
        plus.translatesAutoresizingMaskIntoConstraints = false
        plus.image = DS.symbol("plus", pointSize: 16, weight: .semibold)
        plus.contentTintColor = DS.accentText
        circle.addSubview(plus)
        NSLayoutConstraint.activate([
            plus.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            plus.centerYAnchor.constraint(equalTo: circle.centerYAnchor)
        ])

        let label = DS.label("新建方案", size: 13.5, weight: .medium, color: DS.accentText)

        let stack = NSStackView(views: [circle, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateTrackingAreas()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        if wasPressed && bounds.contains(point) {
            onClick?()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        layer?.backgroundColor = DS.accent.withAlphaComponent(0.04).cgColor
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        layer?.backgroundColor = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
            xRadius: 12,
            yRadius: 12
        )
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        let stroke = isHovering
            ? DS.accent.withAlphaComponent(0.55)
            : NSColor.black.withAlphaComponent(0.22)
        stroke.setStroke()
        path.stroke()
    }
}
