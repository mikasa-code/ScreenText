import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultValue = Shortcut(keyCode: UInt32(kVK_ANSI_C),
                                       modifiers: UInt32(controlKey | optionKey), keyLabel: "C")

    var label: String {
        var result = ""
        for (mask, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(mask) != 0 { result += symbol }
        }
        return result + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }

        var modifiers: UInt32 = 0
        for (flag, mask) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey),
                             (.shift, shiftKey), (.command, cmdKey)] {
            if flags.contains(flag) { modifiers |= UInt32(mask) }
        }

        let specialKeys = [kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                           kVK_Space: "空格", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
                           kVK_ForwardDelete: "⌦", kVK_Home: "Home", kVK_End: "End",
                           kVK_PageUp: "Page Up", kVK_PageDown: "Page Down"]
        let label: String
        if let specialLabel = specialKeys[Int(event.keyCode)] {
            label = specialLabel
        } else if let special = event.specialKey, special.rawValue >= NSEvent.SpecialKey.f1.rawValue,
                  special.rawValue <= NSEvent.SpecialKey.f20.rawValue {
            label = "F\(special.rawValue - NSEvent.SpecialKey.f1.rawValue + 1)"
        } else if let characters = event.characters(byApplyingModifiers: []), !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            label = characters.uppercased()
        } else {
            return nil
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onShortcutChanged: ((Shortcut) -> Bool)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onIconVisibilityChanged: ((Bool) -> Void)?

    private var shortcut: Shortcut
    private let shortcutButton = NSButton()
    private let instruction = NSTextField(wrappingLabelWithString: "点击按钮后按组合键，按 Esc 取消。")
    private var keyMonitor: Any?
    private(set) var isRecording = false

    init(shortcut: Shortcut, showsIcon: Bool) {
        self.shortcut = shortcut
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 228),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ScreenText 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()

        shortcutButton.title = shortcut.label
        shortcutButton.bezelStyle = .rounded
        shortcutButton.target = self
        shortcutButton.action = #selector(toggleRecording)
        shortcutButton.setAccessibilityLabel("录制快捷键")
        shortcutButton.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let row = NSStackView(views: [NSTextField(labelWithString: "取字快捷键"), NSView(), shortcutButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        instruction.font = .systemFont(ofSize: 12)
        instruction.textColor = .secondaryLabelColor

        let iconToggle = NSButton(checkboxWithTitle: "显示菜单栏图标", target: self, action: #selector(toggleIcon(_:)))
        iconToggle.state = showsIcon ? .on : .off
        let hint = NSTextField(wrappingLabelWithString: "隐藏图标后，再次打开 ScreenText 可进入设置。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor

        let quit = NSButton(title: "退出 ScreenText", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let footer = NSStackView(views: [NSView(), quit])
        footer.orientation = .horizontal

        let stack = NSStackView(views: [row, instruction, iconToggle, hint, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            instruction.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    @objc private func toggleRecording() {
        if isRecording {
            finishRecording()
            return
        }
        isRecording = true
        shortcutButton.title = "请按组合键…"
        instruction.stringValue = "包含 Command、Control 或 Option，按 Esc 取消。"
        instruction.textColor = .secondaryLabelColor
        onRecordingChanged?(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.record(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func record(_ event: NSEvent) -> Bool {
        guard event.window === window else {
            finishRecording()
            return false
        }
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return true
        }
        guard let candidate = Shortcut(event: event) else {
            instruction.stringValue = "请加入 Command、Control 或 Option 修饰键。"
            instruction.textColor = .systemRed
            return true
        }
        let accepted = onShortcutChanged?(candidate) == true
        if accepted { shortcut = candidate }
        finishRecording()
        if !accepted {
            instruction.stringValue = "该组合键不可用，已保留原快捷键。"
            instruction.textColor = .systemRed
        }
        return true
    }

    private func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        shortcutButton.title = shortcut.label
        instruction.stringValue = "点击按钮后按组合键，按 Esc 取消。"
        instruction.textColor = .secondaryLabelColor
        onRecordingChanged?(false)
    }

    @objc private func toggleIcon(_ sender: NSButton) {
        onIconVisibilityChanged?(sender.state == .on)
    }

    func windowWillClose(_ notification: Notification) { finishRecording() }
    func windowDidResignKey(_ notification: Notification) { finishRecording() }
}
