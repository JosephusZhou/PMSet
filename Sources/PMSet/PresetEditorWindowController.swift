import AppKit

extension Notification.Name {
    /// 方案仓库发生变化（新建 / 重命名 / 复制 / 删除），AppDelegate 监听后重建菜单
    static let presetStoreDidChange = Notification.Name("PMSet.presetStoreDidChange")
    /// 请求应用某个方案（userInfo["id"]），由 AppDelegate 统一执行与提示
    static let presetApplyRequested = Notification.Name("PMSet.presetApplyRequested")
}

/// 「自定义配置」单例窗口：方案列表（网格）与方案编辑器之间来回切换。
///
/// - 列表态：默认方案 + 自定义方案 + 「+」新建
/// - 编辑态：新建方案与查看 / 编辑方案复用同一个界面（PresetEditorView）
final class PresetEditorWindowController: NSWindowController {

    static let shared = PresetEditorWindowController()

    private let container = NSView()
    private var gridView: PresetGridView!
    private var editorView: PresetEditorView!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "睡眠方案"
        window.minSize = NSSize(width: 660, height: 520)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = DS.canvas

        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = DS.canvas.cgColor
        guard let contentView = window.contentView else { return }
        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        gridView = PresetGridView()
        gridView.onSelect = { [weak self] preset in
            guard let self else { return }
            if preset.isBuiltin {
                self.showEditor(.builtin)
            } else {
                self.showEditor(.existing(preset))
            }
        }
        gridView.onCreate = { [weak self] in self?.showEditor(.new) }

        editorView = PresetEditorView()
        editorView.onBack = { [weak self] in self?.showGrid() }
        editorView.onStoreChanged = { [weak self] in self?.gridView.reload() }
        editorView.onPresetCreated = { [weak self] _ in self?.showGrid() }
        editorView.onCreateFromBuiltin = { [weak self] in self?.showEditor(.new) }

        // 退出全屏后系统会重置红绿灯位置，重新对齐到自定义标题栏中心
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(alignTrafficLights),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 打开窗口：已打开时只前置；否则回到方案列表。
    func show() {
        guard let window = window else { return }
        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showGrid()
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        // 等系统完成标题栏布局后再移动红绿灯
        DispatchQueue.main.async { [weak self] in self?.alignTrafficLights() }
    }

    /// 红绿灯默认在 32pt 系统标题栏里居中（距顶 16pt），
    /// 这里下移到 52pt 自定义标题栏的中心（距顶 26pt）。
    @objc private func alignTrafficLights() {
        guard let window = window else { return }
        let targetCenter: CGFloat = 26
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type),
                  let host = button.superview else { continue }
            let currentCenter = host.isFlipped
                ? button.frame.midY
                : host.bounds.height - button.frame.midY
            let delta = targetCenter - currentCenter
            guard abs(delta) > 0.5 else { continue }
            button.frame.origin.y += host.isFlipped ? delta : -delta
        }
    }

    // MARK: - 页面切换

    private func showGrid() {
        gridView.reload()
        switchChild(to: gridView)
    }

    private func showEditor(_ mode: PresetEditorView.Mode) {
        editorView.load(mode)
        switchChild(to: editorView)
    }

    private func switchChild(to view: NSView) {
        for subview in container.subviews {
            subview.removeFromSuperview()
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
