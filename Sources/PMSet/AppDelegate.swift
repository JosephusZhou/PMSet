import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let manager = PMSetManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "PMSet")
            button.image?.isTemplate = true
            button.toolTip = "PMSet"
        }
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("备份当前配置", #selector(backupConfig)))
        menu.addItem(item("恢复备份配置", #selector(restoreConfig)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("设置合盖不睡眠", #selector(setLidNoSleep)))
        menu.addItem(item("设置合盖睡眠（恢复默认）", #selector(setLidSleep)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("启用 Touch ID 指纹授权", #selector(enableTouchID)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("退出App", #selector(quitApp)))
        return menu
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
        runInBackground { self.manager.restore() }
    }

    @objc private func setLidNoSleep() {
        runInBackground { self.manager.setLidNoSleep() }
    }

    @objc private func setLidSleep() {
        runInBackground { self.manager.setLidSleep() }
    }

    @objc private func enableTouchID() {
        runInBackground { self.manager.enableTouchID() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func runInBackground(_ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
}
