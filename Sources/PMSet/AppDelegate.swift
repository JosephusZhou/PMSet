import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let manager = PMSetManager()
    private var lidNoSleepItem: NSMenuItem?
    private var lidSleepItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "PMSet"
        statusItem = item
        item.menu = makeMenu()
    }

    /// 根据「合盖不睡眠」状态返回菜单栏图标。
    /// 新图标以模板图方式渲染，自动适配浅色/深色菜单栏与选中高亮。
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

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("备份当前配置", #selector(backupConfig)))
        menu.addItem(item("恢复备份配置", #selector(restoreConfig)))
        menu.addItem(NSMenuItem.separator())
        lidNoSleepItem = item("设置合盖不睡眠", #selector(setLidNoSleep))
        lidSleepItem = item("设置合盖睡眠（恢复默认）", #selector(setLidSleep))
        menu.addItem(lidNoSleepItem!)
        menu.addItem(lidSleepItem!)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("退出App", #selector(quitApp)))
        refreshLidState()
        return menu
    }

    /// 根据当前电源设置，在「合盖不睡眠 / 合盖睡眠」前打勾
    private func refreshLidState() {
        let noSleep = manager.isLidNoSleepEnabled()
        lidNoSleepItem?.state = noSleep ? .on : .off
        lidSleepItem?.state = noSleep ? .off : .on
        statusItem?.button?.image = statusIcon(noSleep: noSleep)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func backupConfig() {
        runInBackground { self.manager.backup() }
    }

    @objc private func restoreConfig() {
        runInBackground {
            self.manager.restore()
            DispatchQueue.main.async { self.refreshLidState() }
        }
    }

    @objc private func setLidNoSleep() {
        runInBackground {
            self.manager.setLidNoSleep()
            DispatchQueue.main.async { self.refreshLidState() }
        }
    }

    @objc private func setLidSleep() {
        runInBackground {
            self.manager.setLidSleep()
            DispatchQueue.main.async { self.refreshLidState() }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func runInBackground(_ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
}
