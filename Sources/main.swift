import AppKit
import Carbon
import Vision

private enum CaptureError: LocalizedError {
    case screenshot(String)
    case noText
    case clipboard

    var errorDescription: String? {
        switch self {
        case .screenshot(let message):
            return "截屏失败：\(message)"
        case .noText:
            return "没有识别到文字，请框选清晰的中文或英文。原剪贴板内容未修改。"
        case .clipboard:
            return "文字已识别，但写入剪贴板失败，请重试。"
        }
    }
}

private func recognizeText(at imageURL: URL) async throws -> String {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "en-US")]
    request.automaticallyDetectsLanguage = false

    let observations = try await request.perform(on: imageURL)
    return observations.compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Status { case idle, working, copied }
    private var statusItem: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var captureProcess: Process?
    private var isBusy = false
    private var statusReset: DispatchWorkItem?
    private var settingsController: SettingsWindowController?
    private var shortcutItem: NSMenuItem!
    private var shortcut: Shortcut = {
        guard let data = UserDefaults.standard.data(forKey: "shortcut"),
              let saved = try? JSONDecoder().decode(Shortcut.self, from: data) else { return .defaultValue }
        return saved
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        showStatus(.idle)
        statusItem.isVisible = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true

        let menu = NSMenu()
        shortcutItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        let settingsItem = menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 ScreenText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        updateShortcutLabel()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.capture() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        guard handlerStatus == noErr else {
            showError("无法安装快捷键处理程序，请重新打开 ScreenText。")
            NSApp.terminate(nil)
            return
        }
        if !registerHotKey(shortcut) {
            showError("快捷键 \(shortcut.label) 不可用，请在设置中选择其他组合键。")
            showSettings()
        } else if !statusItem.isVisible {
            showSettings()
        }
    }

    private func registerHotKey(_ candidate: Shortcut) -> Bool {
        var newHotKey: EventHotKeyRef?
        let result = RegisterEventHotKey(candidate.keyCode, candidate.modifiers,
                                         EventHotKeyID(signature: 0x53545854, id: 1),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &newHotKey)
        guard result == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newHotKey
        return true
    }

    private func updateShortcutLabel() {
        shortcutItem.title = "\(shortcut.label) 框选取字"
        statusItem.button?.toolTip = "ScreenText · \(shortcut.label) 框选取字"
    }

    private func showStatus(_ status: Status) {
        let image: NSImage?
        switch status {
        case .idle:
            image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
                NSColor.black.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                for (x, y, dx, dy) in [(2.0, 2.0, 1.0, 1.0), (16, 2, -1, 1),
                                       (2, 16, 1, -1), (16, 16, -1, -1)] {
                    path.move(to: NSPoint(x: x, y: y + dy * 3.5))
                    path.line(to: NSPoint(x: x, y: y))
                    path.line(to: NSPoint(x: x + dx * 3.5, y: y))
                }
                for y in [6.0, 9.0, 12.0] {
                    path.move(to: NSPoint(x: 5, y: y))
                    path.line(to: NSPoint(x: 13, y: y))
                }
                path.stroke()
                return true
            }
        case .working:
            image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "正在识别")
        case .copied:
            image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已复制")
        }
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.title = ""
        statusItem.button?.image = image
    }

    @objc private func showSettings() {
        if settingsController == nil {
            let controller = SettingsWindowController(shortcut: shortcut, showsIcon: statusItem.isVisible)
            controller.onRecordingChanged = { [weak self] recording in
                guard let self else { return }
                if recording {
                    if let hotKey { UnregisterEventHotKey(hotKey) }
                    hotKey = nil
                } else if hotKey == nil, !registerHotKey(shortcut) {
                    showError("原快捷键也已被占用，请重新设置快捷键。")
                }
            }
            controller.onShortcutChanged = { [weak self] candidate in
                guard let self, registerHotKey(candidate) else { return false }
                shortcut = candidate
                UserDefaults.standard.set(try? JSONEncoder().encode(candidate), forKey: "shortcut")
                updateShortcutLabel()
                return true
            }
            controller.onIconVisibilityChanged = { [weak self] visible in
                self?.statusItem.isVisible = visible
                UserDefaults.standard.set(visible, forKey: "showMenuBarIcon")
            }
            settingsController = controller
        }
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func capture() {
        guard !isBusy, settingsController?.isRecording != true else { return }
        isBusy = true
        statusReset?.cancel()
        showStatus(.working)

        Task {
            var copied = false
            let imageURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScreenText-\(UUID().uuidString).png")
            defer {
                try? FileManager.default.removeItem(at: imageURL)
                isBusy = false
                if !copied { showStatus(.idle) }
            }

            do {
                guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                    showError("请在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中允许 ScreenText，然后退出并重新打开它。")
                    return
                }
                guard try await takeScreenshot(to: imageURL) else { return }
                let text = try await recognizeText(at: imageURL)
                guard !text.isEmpty else { throw CaptureError.noText }

                let clipboard = NSPasteboard.general
                clipboard.clearContents()
                guard clipboard.setString(text, forType: .string) else { throw CaptureError.clipboard }

                copied = true
                showStatus(.copied)
                let reset = DispatchWorkItem { [weak self] in
                    self?.showStatus(.idle)
                }
                statusReset = reset
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: reset)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func takeScreenshot(to imageURL: URL) async throws -> Bool {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", imageURL.path]
        process.standardError = errors
        captureProcess = process
        defer { captureProcess = nil }

        let exitStatus: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let imageExists = FileManager.default.fileExists(atPath: imageURL.path)
        // Esc exits without creating a file or reporting an error.
        if !imageExists, errorText.isEmpty, exitStatus == 1 { return false }
        guard exitStatus == 0, imageExists else {
            throw CaptureError.screenshot(errorText.isEmpty ? "未能取得屏幕图像（\(exitStatus)）" : errorText)
        }
        return true
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ScreenText"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let captureProcess, captureProcess.isRunning { captureProcess.terminate() }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()
