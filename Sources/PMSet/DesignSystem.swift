import AppKit

// MARK: - 设计常量

/// 界面设计稿（docs/design/pages/界面设计.html）里的视觉常量与通用控件。
///
/// 全部用代码实现，避免 Storyboard / XIB；颜色值直接取自设计稿。
enum DS {

    // 画布与底色
    static let canvas = rgb(0xF5F5F7)
    static let headerBar = rgb(0xECECEE)
    static let card = NSColor.white
    static let disabledOverlay = rgb(0xE5E5EA, alpha: 0.52)

    // 文字
    static let text = rgb(0x1D1D1F)
    static let secondaryText = rgb(0x6E6E73)

    // 强调色
    static let accent = rgb(0x0071E3)
    static let accentText = rgb(0x0062C4)
    static let accentFaint = rgb(0x0071E3, alpha: 0.10)

    // 分隔线与边框
    static let cardBorder = NSColor.black.withAlphaComponent(0.06)
    static let rowSeparator = NSColor.black.withAlphaComponent(0.07)
    static let barSeparator = NSColor.black.withAlphaComponent(0.08)
    static let controlBorder = NSColor.black.withAlphaComponent(0.15)
    static let inputBorder = NSColor.black.withAlphaComponent(0.18)
    static let toggleOff = rgb(0xE3E3E8)
    static let toggleOffRing = NSColor.black.withAlphaComponent(0.12)

    // 提示
    static let warningText = rgb(0x8A4600)
    static let warningIcon = rgb(0xC76A00)
    static let warningBackground = rgb(0xFF9500, alpha: 0.12)
    static let danger = rgb(0xC4001A)

    // 方案方块
    static let builtinIcon = rgb(0x5856D6)
    static let customIcon = rgb(0x30A2B8)

    // MARK: 字体

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: 文字控件

    static func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = DS.text
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font(size, weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func wrappingLabel(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = DS.secondaryText
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font(size, weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func spacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return spacer
    }

    /// 一像素分隔线。
    static func divider(color: NSColor = DS.rowSeparator) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    /// 取 SF Symbol，并按字号与字重配置。
    static func symbol(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    // MARK: 颜色工具

    static func rgb(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - 容器

/// 白底圆角卡片：12pt 圆角、1px 淡边框、极轻阴影。
class DSCardView: NSView {

    init(radius: CGFloat = 12) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = DS.card.cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = 1
        layer?.borderColor = DS.cardBorder.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 1
        layer?.shadowOffset = CGSize(width: 0, height: -1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 翻转坐标系的竖向栈：用作 NSScrollView 的文档视图，内容从顶部开始。
final class DSFlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

// MARK: - 顶部标题栏

/// 52pt 高的窗口内标题栏：左侧返回、标题、右侧「+」。
///
/// 窗口使用 fullSizeContentView，红绿灯按钮直接叠在这条栏上，
/// 因此正文左侧留出 84 / 92pt 避开系统按钮。
final class DSHeaderBar: NSView {

    var onBack: (() -> Void)?
    var onPlus: (() -> Void)?

    private let titleLabel = DS.label("", size: 15, weight: .semibold, color: DS.text)

    init(showsBack: Bool, showsPlus: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = DS.headerBar.cgColor
        heightAnchor.constraint(equalToConstant: 52).isActive = true

        let bottomLine = DS.divider(color: NSColor.black.withAlphaComponent(0.10))
        addSubview(bottomLine)
        NSLayoutConstraint.activate([
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        addSubview(titleLabel)

        if showsBack {
            let back = DSIconButton(
                symbol: "chevron.left",
                accessibilityLabel: "返回",
                target: self,
                action: #selector(backClicked)
            )
            addSubview(back)
            NSLayoutConstraint.activate([
                back.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 84),
                back.centerYAnchor.constraint(equalTo: centerYAnchor),
                back.widthAnchor.constraint(equalToConstant: 30),
                back.heightAnchor.constraint(equalToConstant: 30),

                titleLabel.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 16),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else {
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 92).isActive = true
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }

        if showsPlus {
            let plus = DSIconButton(
                symbol: "plus",
                accessibilityLabel: "新建方案",
                target: self,
                action: #selector(plusClicked)
            )
            addSubview(plus)
            NSLayoutConstraint.activate([
                plus.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                plus.centerYAnchor.constraint(equalTo: centerYAnchor),
                plus.widthAnchor.constraint(equalToConstant: 30),
                plus.heightAnchor.constraint(equalToConstant: 30),

                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: plus.leadingAnchor, constant: -12)
            ])
        } else {
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16).isActive = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ text: String) {
        titleLabel.stringValue = text
    }

    /// 标题栏空白处可以拖动窗口。
    override var mouseDownCanMoveWindow: Bool { true }

    @objc private func backClicked() {
        onBack?()
    }

    @objc private func plusClicked() {
        onPlus?()
    }
}

// MARK: - 按钮

/// 30pt 高的白底图标按钮（返回、加号）。
final class DSIconButton: NSButton {

    init(symbol: String, accessibilityLabel: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.10).cgColor

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(config)
        imageScaling = .scaleProportionallyDown
        contentTintColor = DS.text
        setAccessibilityLabel(accessibilityLabel)

        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 底部操作按钮：30pt 高、8pt 圆角，分主次两种样式。
final class DSButton: NSButton {

    enum Style {
        case primary
        case secondary
    }

    init(
        title: String,
        style: Style,
        textColor: NSColor? = nil,
        target: AnyObject?,
        action: Selector?
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = 8
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        let font = DS.font(13, style == .primary ? .semibold : .medium)
        let color: NSColor
        switch style {
        case .primary:
            color = .white
            layer?.backgroundColor = DS.accent.cgColor
        case .secondary:
            color = textColor ?? DS.text
            layer?.backgroundColor = NSColor.white.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        }
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: font, .foregroundColor: color]
        )

        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = attributedTitle.size().width
        return NSSize(width: ceil(textWidth) + 32, height: 30)
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.5 }
    }
}

// MARK: - 标签 / 徽标

/// 带内边距的小标签：键名 chip、内置 / 自定义徽标都用它。
final class DSPaddedLabel: NSView {

    private let label: NSTextField

    init(
        text: String,
        font: NSFont,
        textColor: NSColor,
        background: NSColor?,
        cornerRadius: CGFloat,
        insets: NSEdgeInsets = NSEdgeInsets(top: 2, left: 7, bottom: 2, right: 7),
        symbol: String? = nil,
        symbolSize: CGFloat = 10
    ) {
        label = DS.label(text, size: font.pointSize, color: textColor)
        label.font = font
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.backgroundColor = background?.cgColor
        setContentHuggingPriority(.required, for: .horizontal)

        var views: [NSView] = []
        if let symbol {
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.image = DS.symbol(symbol, pointSize: symbolSize, weight: .semibold)
            icon.contentTintColor = textColor
            icon.widthAnchor.constraint(equalToConstant: symbolSize + 1).isActive = true
            icon.heightAnchor.constraint(equalToConstant: symbolSize + 1).isActive = true
            views.append(icon)
        }
        views.append(label)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - 开关

/// 40×24 的开关，视觉按设计稿自绘（系统 NSSwitch 尺寸与配色不一致）。
/// 支持 nil（未配置／沿用系统当前值）三态展示，点击后在开／关间切换，右键可恢复沿用系统。
final class DSToggleView: NSView {

    var onChange: ((Bool?) -> Void)?

    var state: Bool? = nil {
        didSet {
            updateAppearance()
            needsLayout = true
        }
    }

    var isEnabled: Bool = true {
        didSet { updateAppearance() }
    }

    private let knob = NSView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        widthAnchor.constraint(equalToConstant: 40).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true

        knob.translatesAutoresizingMaskIntoConstraints = true
        knob.wantsLayer = true
        knob.layer?.backgroundColor = NSColor.white.cgColor
        knob.layer?.cornerRadius = 10
        knob.layer?.shadowColor = NSColor.black.cgColor
        knob.layer?.shadowOpacity = 0.30
        knob.layer?.shadowRadius = 3
        knob.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(knob)

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 40, height: 24)
    }

    override func layout() {
        super.layout()
        let x: CGFloat
        switch state {
        case nil: x = 10
        case false?: x = 2
        case true?: x = 18
        }
        knob.frame = NSRect(x: x, y: 2, width: 20, height: 20)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        state = (state == true) ? false : true
        onChange?(state)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isEnabled, state != nil else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "沿用系统（不修改）", action: #selector(resetToUnset), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func resetToUnset() {
        guard isEnabled else { return }
        state = nil
        onChange?(nil)
    }

    override func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    private func updateAppearance() {
        let isOn = state == true
        layer?.cornerRadius = 12
        layer?.backgroundColor = (isOn ? DS.accent : DS.toggleOff).cgColor
        layer?.borderWidth = isOn ? 0 : 1
        layer?.borderColor = DS.toggleOffRing.cgColor
        knob.alphaValue = state == nil ? 0.72 : 1
        alphaValue = isEnabled ? 1 : 0.45
        toolTip = state == nil ? "未配置（沿用系统当前值）；点击设为开启" : "右键可恢复为沿用系统"
        needsLayout = true
    }
}

// MARK: - 分钟输入

/// 「数值框 + 分钟 + 加减」控件，数值框可直接输入；留空表示未配置（沿用系统当前值）。
final class DSMinutesControl: NSView, NSTextFieldDelegate {

    /// 数值变化（输入或点加减）时回调；nil 表示清空为「沿用系统」。
    var onValueChange: ((Int?) -> Void)?

    /// 只读场景（内置方案）下只显示「N 分钟」或「沿用系统」纯文本。
    var readOnly: Bool = false {
        didSet { updateMode() }
    }

    var isEditable: Bool = true {
        didSet { updateMode() }
    }

    var value: Int? = nil {
        didSet {
            if let value {
                field.stringValue = String(value)
                plainLabel.stringValue = "\(value) 分钟"
            } else {
                field.stringValue = ""
                plainLabel.stringValue = "沿用系统"
            }
            field.textColor = DS.text
            if readOnly {
                widthConstraint.constant = ceil(plainLabel.intrinsicContentSize.width) + 2
            }
        }
    }

    var currentValue: Int? {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let value = Int(text), value >= 0 else { return nil }
        return value
    }

    /// 留空（沿用系统）或合法的非负整数都算有效输入。
    var isValidInput: Bool {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return true }
        guard let value = Int(text), value >= 0 else { return false }
        return true
    }

    private let valueBox = NSView()
    private let field = NSTextField()
    private let plainLabel = DS.label("", size: 13, color: DS.secondaryText)
    private let unitLabel = DS.label("分钟", size: 13, color: DS.secondaryText)
    private let stepper = NSView()
    private let minusButton: DSStepperButton
    private let plusButton: DSStepperButton
    private var widthConstraint: NSLayoutConstraint!

    init() {
        minusButton = DSStepperButton(symbol: "minus", label: "减少 1 分钟", target: nil, action: nil)
        plusButton = DSStepperButton(symbol: "plus", label: "增加 1 分钟", target: nil, action: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 158)
        widthConstraint.isActive = true

        // 数值框：白底细边框，内部是无边框文本框
        valueBox.translatesAutoresizingMaskIntoConstraints = false
        valueBox.wantsLayer = true
        valueBox.layer?.backgroundColor = NSColor.white.cgColor
        valueBox.layer?.cornerRadius = 6
        valueBox.layer?.borderWidth = 1
        valueBox.layer?.borderColor = DS.controlBorder.cgColor

        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.textColor = DS.text
        field.placeholderString = "沿用"
        field.delegate = self
        valueBox.addSubview(field)
        NSLayoutConstraint.activate([
            valueBox.widthAnchor.constraint(equalToConstant: 52),
            valueBox.heightAnchor.constraint(equalToConstant: 26),
            field.leadingAnchor.constraint(equalTo: valueBox.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: valueBox.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: valueBox.centerYAnchor)
        ])

        // 加减按钮组
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.wantsLayer = true
        stepper.layer?.backgroundColor = NSColor.white.cgColor
        stepper.layer?.cornerRadius = 7
        stepper.layer?.borderWidth = 1
        stepper.layer?.borderColor = DS.controlBorder.cgColor
        stepper.layer?.masksToBounds = true

        minusButton.target = self
        minusButton.action = #selector(decrease)
        plusButton.target = self
        plusButton.action = #selector(increase)

        let stepDivider = NSView()
        stepDivider.translatesAutoresizingMaskIntoConstraints = false
        stepDivider.wantsLayer = true
        stepDivider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor

        let stepStack = NSStackView(views: [minusButton, stepDivider, plusButton])
        stepStack.orientation = .horizontal
        stepStack.alignment = .centerY
        stepStack.spacing = 0
        stepStack.translatesAutoresizingMaskIntoConstraints = false
        stepper.addSubview(stepStack)
        NSLayoutConstraint.activate([
            stepper.widthAnchor.constraint(equalToConstant: 60),
            stepper.heightAnchor.constraint(equalToConstant: 26),
            stepDivider.widthAnchor.constraint(equalToConstant: 1),
            stepDivider.heightAnchor.constraint(equalToConstant: 26),
            stepStack.leadingAnchor.constraint(equalTo: stepper.leadingAnchor),
            stepStack.trailingAnchor.constraint(equalTo: stepper.trailingAnchor),
            stepStack.topAnchor.constraint(equalTo: stepper.topAnchor),
            stepStack.bottomAnchor.constraint(equalTo: stepper.bottomAnchor)
        ])

        plainLabel.isHidden = true
        plainLabel.setContentHuggingPriority(.required, for: .horizontal)
        plainLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [valueBox, unitLabel, stepper, plainLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateMode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setValue(_ value: Int?) {
        self.value = value
    }

    private func updateMode() {
        let plain = readOnly
        valueBox.isHidden = plain
        unitLabel.isHidden = plain
        stepper.isHidden = plain
        plainLabel.isHidden = !plain

        // 只读时收窄到纯文本宽度，让数值贴住右侧；可编辑时容纳输入框与加减按钮
        widthConstraint.constant = plain
            ? ceil(plainLabel.intrinsicContentSize.width) + 2
            : 158

        field.isEditable = isEditable && !plain
        field.isSelectable = isEditable && !plain
        minusButton.isEnabled = isEditable && !plain
        plusButton.isEnabled = isEditable && !plain
    }

    @objc private func decrease() {
        adjust(by: -1)
    }

    @objc private func increase() {
        adjust(by: 1)
    }

    private func adjust(by delta: Int) {
        let next = max(0, (currentValue ?? 0) + delta)
        value = next
        onValueChange?(next)
    }

    func controlTextDidChange(_ obj: Notification) {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            field.textColor = DS.text
            plainLabel.stringValue = "沿用系统"
            onValueChange?(nil)
        } else if let value = Int(text), value >= 0 {
            field.textColor = DS.text
            plainLabel.stringValue = "\(value) 分钟"
            onValueChange?(value)
        } else {
            field.textColor = DS.danger
        }
    }
}

/// 加减按钮组里的小按钮。
final class DSStepperButton: NSButton {

    private var isHovering = false

    init(symbol: String, label: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        image = DS.symbol(symbol, pointSize: 11, weight: .semibold)
        imageScaling = .scaleProportionallyDown
        contentTintColor = DS.text
        setAccessibilityLabel(label)

        self.target = target
        self.action = action

        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

// MARK: - 输入框

/// 白底细边框输入框（方案名称）。
final class DSInputField: NSView {

    let field = NSTextField()

    init(width: CGFloat, height: CGFloat = 28) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = DS.inputBorder.cgColor

        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = DS.font(13.5)
        field.textColor = DS.text
        addSubview(field)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }
}

// MARK: - 提示

/// 置灰控件的点击拦截层：点击时说明「为什么现在不能改」。
final class DSBlockerView: NSView {

    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// 橙色横幅提示（整组说明用）。
final class DSWarningBanner: NSView {

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = DS.warningBackground.cgColor
        layer?.cornerRadius = 10

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = DS.symbol("exclamationmark.triangle", pointSize: 14, weight: .regular)
        icon.contentTintColor = DS.warningIcon
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let label = DS.wrappingLabel(text, size: 12.5, color: DS.warningText)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 提示气泡内容：一段会自动折行的说明文字。
final class DSTipViewController: NSViewController {

    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let maxWidth: CGFloat = 260
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 10
        let maxTextWidth = maxWidth - horizontalPadding * 2

        let label = DS.wrappingLabel(text, size: 12, color: DS.text)
        label.maximumNumberOfLines = 6
        label.preferredMaxLayoutWidth = maxTextWidth

        let fitted = label.sizeThatFits(
            NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude)
        )
        let textWidth = min(maxTextWidth, ceil(fitted.width))
        label.preferredMaxLayoutWidth = textWidth

        let contentSize = NSSize(
            width: textWidth + horizontalPadding * 2,
            height: ceil(fitted.height) + verticalPadding * 2
        )

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.wantsLayer = true
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentSize.width),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: verticalPadding),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -verticalPadding)
        ])
        view = container
        preferredContentSize = contentSize
    }
}
