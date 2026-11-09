import AppKit
import Carbon

@main
struct ShortcutTests {
    @MainActor
    static func main() throws {
        var passed = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else {
                FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8))
                exit(1)
            }
            passed += 1
            print("PASS: \(name)")
        }

        func keyEvent(_ code: Int, flags: NSEvent.ModifierFlags, characters: String) -> NSEvent {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: UInt16(code)
            ) else {
                fatalError("Could not create a keyboard event")
            }
            return event
        }

        let defaultShortcut = Shortcut.defaultValue
        check(defaultShortcut.keyCode == UInt32(kVK_ANSI_C)
              && defaultShortcut.modifiers == UInt32(controlKey | optionKey)
              && defaultShortcut.label == "⌃⌥C", "default shortcut")

        check(Shortcut(event: keyEvent(kVK_ANSI_C, flags: [], characters: "c")) == nil,
              "reject a key without modifiers")
        check(Shortcut(event: keyEvent(kVK_ANSI_C, flags: [.shift], characters: "C")) == nil,
              "reject Shift as the only modifier")

        let letter = Shortcut(event: keyEvent(kVK_ANSI_X, flags: [.control, .option], characters: "x"))
        check(letter?.keyCode == UInt32(kVK_ANSI_X)
              && letter?.modifiers == UInt32(controlKey | optionKey), "record Control and Option")

        let arrow = Shortcut(event: keyEvent(kVK_UpArrow, flags: [.command, .option], characters: "\u{f700}"))
        check(arrow?.label == "⌥⌘↑", "record an arrow key")

        let function = Shortcut(event: keyEvent(kVK_F2, flags: [.control, .option, .function], characters: "\u{f705}"))
        check(function?.label == "⌃⌥F2", "record a function key")

        let encoded = try JSONEncoder().encode(defaultShortcut)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: encoded)
        check(decoded == defaultShortcut, "save and restore a shortcut")

        let malformed = Data("{}".utf8)
        check((try? JSONDecoder().decode(Shortcut.self, from: malformed)) == nil,
              "reject an incomplete saved shortcut")

        let allModifiers = Shortcut(keyCode: UInt32(kVK_ANSI_C),
                                    modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey),
                                    keyLabel: "C")
        check(allModifiers.label == "⌃⌥⇧⌘C", "display modifiers in a consistent order")
        print("\(passed) checks passed")
    }
}
