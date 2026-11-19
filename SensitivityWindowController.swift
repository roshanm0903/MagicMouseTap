import Cocoa

private enum SensitivitySetting: CaseIterable {
    case tapSensitivity
    case tapDuration
    case cursorMovementTolerance
    case surfaceMovementTolerance
    case doubleTapInterval
    case zoomSwipeDistance
    case dragStartDistance
    case scrollStopWindow

    var title: String {
        switch self {
        case .tapSensitivity: return "Tap sensitivity"
        case .tapDuration: return "Tap speed"
        case .cursorMovementTolerance: return "Hand jitter allowance"
        case .surfaceMovementTolerance: return "Finger movement allowance"
        case .doubleTapInterval: return "Double-tap timing"
        case .zoomSwipeDistance: return "Zoom swipe distance"
        case .dragStartDistance: return "Drag activation distance"
        case .scrollStopWindow: return "Scroll-stop protection"
        }
    }

    var help: String {
        switch self {
        case .tapSensitivity:
            return "Lower rejects more accidental touches; higher makes taps easier."
        case .tapDuration:
            return "How long your finger may rest and still count as a tap."
        case .cursorMovementTolerance:
            return "How much the whole mouse may wobble during a tap."
        case .surfaceMovementTolerance:
            return "How far your finger may move before the touch is treated as scrolling."
        case .doubleTapInterval:
            return "Maximum pause allowed between the first and second tap."
        case .zoomSwipeDistance:
            return "Finger travel needed to trigger zoom. Lower reacts sooner."
        case .dragStartDistance:
            return "Mouse travel needed to begin selection or drag-and-drop."
        case .scrollStopWindow:
            return "How long a tap after scrolling only stops motion instead of clicking."
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .tapSensitivity: return 0.0...1.0
        case .tapDuration: return 0.15...0.50
        case .cursorMovementTolerance: return 0.25...8.0
        case .surfaceMovementTolerance: return 0.02...0.10
        case .doubleTapInterval: return 0.25...0.85
        case .zoomSwipeDistance: return 0.015...0.10
        case .dragStartDistance: return 2.0...20.0
        case .scrollStopWindow: return 0.15...0.70
        }
    }

    var value: Double {
        switch self {
        case .tapSensitivity: return Preferences.tapSensitivity
        case .tapDuration: return Preferences.tapDuration
        case .cursorMovementTolerance: return Preferences.cursorMovementTolerance
        case .surfaceMovementTolerance: return Preferences.surfaceMovementTolerance
        case .doubleTapInterval: return Preferences.doubleTapInterval
        case .zoomSwipeDistance: return Preferences.zoomSwipeDistance
        case .dragStartDistance: return Preferences.dragStartDistance
        case .scrollStopWindow: return Preferences.scrollStopWindow
        }
    }

    func save(_ value: Double) {
        switch self {
        case .tapSensitivity: Preferences.tapSensitivity = value
        case .tapDuration: Preferences.tapDuration = value
        case .cursorMovementTolerance: Preferences.cursorMovementTolerance = value
        case .surfaceMovementTolerance: Preferences.surfaceMovementTolerance = value
        case .doubleTapInterval: Preferences.doubleTapInterval = value
        case .zoomSwipeDistance: Preferences.zoomSwipeDistance = value
        case .dragStartDistance: Preferences.dragStartDistance = value
        case .scrollStopWindow: Preferences.scrollStopWindow = value
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .tapSensitivity:
            return "\(Int((value * 100).rounded()))%"
        case .tapDuration, .doubleTapInterval, .scrollStopWindow:
            return "\(Int((value * 1000).rounded())) ms"
        case .cursorMovementTolerance, .dragStartDistance:
            return String(format: "%.1f px", value)
        case .surfaceMovementTolerance, .zoomSwipeDistance:
            return String(format: "%.1f%%", value * 100)
        }
    }
}

private final class SensitivitySliderRow: NSView {
    let setting: SensitivitySetting
    private let slider: NSSlider
    private let valueLabel: NSTextField
    var onChange: (() -> Void)?

    init(setting: SensitivitySetting) {
        self.setting = setting
        slider = NSSlider(
            value: setting.value,
            minValue: setting.range.lowerBound,
            maxValue: setting.range.upperBound,
            target: nil,
            action: nil
        )
        valueLabel = NSTextField(labelWithString: setting.formatted(setting.value))
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true

        let titleLabel = NSTextField(labelWithString: setting.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        let helpLabel = NSTextField(wrappingLabelWithString: setting.help)
        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.maximumNumberOfLines = 1

        [titleLabel, valueLabel, helpLabel, slider].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 64),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 78),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -8),
            helpLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            helpLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            helpLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor),
            slider.topAnchor.constraint(equalTo: helpLabel.bottomAnchor, constant: 5)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderChanged() {
        setting.save(slider.doubleValue)
        valueLabel.stringValue = setting.formatted(setting.value)
        onChange?()
    }

    func reload() {
        slider.doubleValue = setting.value
        valueLabel.stringValue = setting.formatted(setting.value)
    }
}

final class SensitivityWindowController: NSWindowController, NSWindowDelegate {
    private var rows: [SensitivitySliderRow] = []
    private let onPreferencesChanged: () -> Void

    init(onPreferencesChanged: @escaping () -> Void) {
        self.onPreferencesChanged = onPreferencesChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 735),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gesture Sensitivity"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        rows.forEach { $0.reload() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Tune the gestures to your hand")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(wrappingLabelWithString:
            "Changes apply immediately and are saved automatically. Scroll and click safety checks remain active."
        )
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(18, after: subtitle)

        for setting in SensitivitySetting.allCases {
            let row = SensitivitySliderRow(setting: setting)
            row.onChange = { [weak self] in self?.preferencesChanged() }
            rows.append(row)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        buttonRow.addArrangedSubview(resetButton)
        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(doneButton)
        stack.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 25),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])
    }

    private func preferencesChanged() {
        onPreferencesChanged()
    }

    @objc private func resetToDefaults() {
        Preferences.resetGestureSensitivity()
        rows.forEach { $0.reload() }
        preferencesChanged()
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
