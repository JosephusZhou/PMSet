import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private let manager = PMSetManager()

    /// 首次启动的禁止睡眠提示只弹一次
    private var didShowStartupWarning = false
    /// 避免重复弹出 Helper 安装 / 卸载授权框
    private var isManagingHelper = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "PMSet"
        statusItem = item

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu

        rebuildMenu()
        checkSleepDisabledAtLaunch()

        // 配置窗口内保存 / 管理方案后，需要立即刷新菜单
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(presetStoreDidChange),
            name: .presetStoreDidChange,
            object: nil
        )
        // 首页右键菜单里的「应用」
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(presetApplyRequested(_:)),
            name: .presetApplyRequested,
            object: nil
        )
    }

    // MARK: - 菜单刷新

    /// 每次菜单展开前重建全部菜单项，保证方案增删、勾选状态与系统实际值同步。
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusItem?.menu {
            rebuildMenu()
        }
    }

    @objc private func presetStoreDidChange() {
        rebuildMenu()
    }

    @objc private func presetApplyRequested(_ notification: Notification) {
        guard let id = notification.userInfo?["id"] as? String,
              let preset = PresetStore.shared.preset(id: id) else { return }
        applyPreset(preset)
    }

    /// 按固定顺序重建菜单：查看方案 / 分隔线 / 默认睡眠方案 / 前两个自定义方案 /
    /// 更多（条件） / 分隔线 / 辅助工具状态 / 当前版本 / 关于 / 退出。
    func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let snapshot = SystemPowerReader().snapshot()
        let checkedID = checkedPresetID(snapshot: snapshot)
        let customs = PresetStore.shared.customPresets

        menu.addItem(item("查看方案", #selector(openPresetEditor)))
        menu.addItem(NSMenuItem.separator())

        let builtin = PresetStore.shared.builtinPreset
        menu.addItem(presetItem(builtin, checked: builtin.id == checkedID))

        for preset in customs.prefix(2) {
            menu.addItem(presetItem(preset, checked: preset.id == checkedID))
        }

        let remaining = customs.dropFirst(2)
        if !remaining.isEmpty {
            let moreItem = NSMenuItem(title: "更多", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for preset in remaining {
                submenu.addItem(presetItem(preset, checked: preset.id == checkedID))
            }
            moreItem.submenu = submenu
            menu.addItem(moreItem)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(helperStatusItem())
        // 版本号仅作展示：不设置 action，点击无响应
        menu.addItem(
            NSMenuItem(title: "当前版本：v\(Bundle.main.version)", action: nil, keyEquivalent: "")
        )
        menu.addItem(item("关于", #selector(openAbout)))
        menu.addItem(item("退出", #selector(quitApp)))

        // 图标以回读的实际值为准
        statusItem?.button?.image = statusIcon(noSleep: snapshot.sleepDisabled)
    }

    // MARK: - 勾选判定

    /// 勾选以回读的实际值为准：只比较方案里出现且本机可用的键，值为 0 与「缺失」不同。
    /// 内置方案 values 为空时退化为按 activePresetID 判定。
    private func matches(_ preset: Preset, snapshot: PowerSnapshot) -> Bool {
        let comparable = preset.values.filter { snapshot.isAvailable($0.key) }
        guard !comparable.isEmpty else {
            return PresetStore.shared.activePresetID == preset.id
        }
        if preset.isBuiltin {
            return snapshot.matchesBuiltinDefault(comparable: comparable)
        }
        return comparable.allSatisfy { snapshot.matchesAllPowerModes($0.key, target: $0.value) }
    }

    /// 同一时刻只允许一个勾选：优先取当前生效方案，其次取第一个与实际值一致的方案。
    private func checkedPresetID(snapshot: PowerSnapshot) -> String? {
        let all = [PresetStore.shared.builtinPreset] + PresetStore.shared.customPresets
        let matching = all.filter { matches($0, snapshot: snapshot) }
        let activeID = PresetStore.shared.activePresetID
        if matching.contains(where: { $0.id == activeID }) {
            return activeID
        }
        return matching.first?.id
    }

    // MARK: - 菜单项构造

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    private func presetItem(_ preset: Preset, checked: Bool) -> NSMenuItem {
        let menuItem = item(preset.name, #selector(presetClicked(_:)))
        menuItem.representedObject = preset.id
        menuItem.state = checked ? .on : .off
        return menuItem
    }

    private func helperStatusItem() -> NSMenuItem {
        let installed = PrivilegedHelperManager.shared.isHelperInstalled
        let title = isManagingHelper
            ? "辅助工具：处理中..."
            : (installed ? "辅助工具：已安装" : "辅助工具：未安装")
        let menuItem = item(title, #selector(toggleHelperInstall))
        menuItem.isEnabled = !isManagingHelper
        return menuItem
    }

    /// 根据「禁止睡眠」状态返回菜单栏图标（模板图，自动适配浅色/深色菜单栏）。
    private func statusIcon(noSleep: Bool) -> NSImage? {
        let name = noSleep ? "MenuBarAwake" : "MenuBarSleep"
        if let image = NSImage(named: name) {
            image.isTemplate = true
            return image
        }
        // 开发环境（swift run，无 Resources）下回退到系统符号
        return NSImage(
            systemSymbolName: noSleep ? "bolt.fill" : "moon.zzz.fill",
            accessibilityDescription: "PMSet"
        )
    }

    // MARK: - 动作

    @objc private func openPresetEditor() {
        PresetEditorWindowController.shared.show()
    }

    @objc private func presetClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = PresetStore.shared.preset(id: id) else { return }
        applyPreset(preset)
    }

    private func applyPreset(_ preset: Preset) {
        manager.applyPreset(preset) { report in
            // 无论成功与否都重建菜单与图标，勾选状态以回读实际值为准
            self.rebuildMenu()
            // 成功且没有下发任何键时不弹窗，避免噪音
            if report.failedKeys.isEmpty && report.appliedKeys.isEmpty { return }
            // 已弹过「不会立即入睡」的询问框，不再追加成功弹窗（失败仍要提示）
            if report.failedKeys.isEmpty && report.promptedSleepNow { return }
            self.showReport(report, presetName: preset.name)
        }
    }

    /// 汇总应用结果：失败时列出具体键名与原因。
    private func showReport(_ report: ApplyReport, presetName: String) {
        var lines: [String] = []
        if !report.message.isEmpty {
            lines.append(report.message)
        }
        let failed = report.failedKeys.sorted { $0.key < $1.key }
        if !failed.isEmpty {
            lines.append(failed.map { "• \($0.key)：\($0.value)" }.joined(separator: "\n"))
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = failed.isEmpty ? .informational : .warning
        alert.messageText = failed.isEmpty ? "「\(presetName)」已应用" : "「\(presetName)」应用未完成"
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func toggleHelperInstall() {
        guard !isManagingHelper else { return }

        let installed = PrivilegedHelperManager.shared.isHelperInstalled
        let alert = NSAlert()
        alert.alertStyle = installed ? .warning : .informational
        alert.messageText = installed ? "卸载辅助工具？" : "安装辅助工具？"
        alert.informativeText = installed
            ? "卸载后，修改电源设置将不再免密静默执行，每次需要输入管理员密码。"
            : "安装后，修改电源设置可免密静默执行。安装过程需要输入一次管理员密码完成授权。"
        alert.addButton(withTitle: installed ? "卸载" : "安装")
        alert.addButton(withTitle: "取消")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isManagingHelper = true
        rebuildMenu()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = installed
                ? PrivilegedHelperManager.shared.uninstallHelper()
                : PrivilegedHelperManager.shared.installHelper()

            DispatchQueue.main.async {
                self.isManagingHelper = false
                self.rebuildMenu()

                if result.success {
                    self.showSimpleAlert(
                        title: installed ? "辅助工具已卸载" : "辅助工具已安装",
                        message: installed
                            ? "后续修改电源设置将恢复为通过管理员密码授权执行。"
                            : "后续修改电源设置将通过辅助工具静默执行，不再每次提示输入密码。",
                        style: .informational
                    )
                } else if !result.canceled {
                    self.showSimpleAlert(
                        title: installed ? "辅助工具卸载失败" : "辅助工具安装失败",
                        message: result.errorMessage,
                        style: .warning
                    )
                }
            }
        }
    }

    private func showSimpleAlert(title: String, message: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func openAbout() {
        guard let url = URL(string: "https://github.com/JosephusZhou/PMSet") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - 首次启动提示

    /// 首次启动检测到「禁止睡眠」时提示一次，只提示，不自动修改配置。
    private func checkSleepDisabledAtLaunch() {
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = SystemPowerReader().snapshot()
            guard snapshot.sleepDisabled else { return }
            DispatchQueue.main.async {
                guard !self.didShowStartupWarning else { return }
                self.didShowStartupWarning = true
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "当前处于「禁止睡眠」状态"
                alert.informativeText = "当前处于『禁止睡眠』状态（合盖也不会睡），建议切换到『默认睡眠方案』恢复。"
                alert.addButton(withTitle: "知道了")
                alert.runModal()
            }
        }
    }
}

private extension Bundle {
    /// 应用版本号，取自 Info.plist；开发环境下无该字段时回退为「未知」。
    var version: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }
}
