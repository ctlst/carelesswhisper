import ApplicationServices
import CoreGraphics
import Foundation

final class Typer {
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func type(_ string: String, submit: Bool) {
        guard hasAccessibilityPermission else { return }
        let source = CGEventSource(stateID: .hidSystemState)

        for scalar in string.unicodeScalars {
            var ch = UniChar(scalar.value & 0xFFFF)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        if submit {
            pressReturn(source: source)
        }
    }

    func undo() {
        pressKey(virtualKey: 0x06, flags: .maskCommand)
    }

    func redo() {
        pressKey(virtualKey: 0x06, flags: [.maskCommand, .maskShift])
    }

    private func pressReturn(source: CGEventSource?) {
        let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        returnDown?.post(tap: .cghidEventTap)
        returnUp?.post(tap: .cghidEventTap)
    }

    private func pressKey(virtualKey: CGKeyCode, flags: CGEventFlags = []) {
        guard hasAccessibilityPermission else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
