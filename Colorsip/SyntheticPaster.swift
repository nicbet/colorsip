import AppKit
import ColorsipCore

/// Pastes into another app (`spec.md` §4.5): activates it and, once it is frontmost, sends a
/// synthetic Cmd+V. Posting key events needs the Accessibility permission.
@MainActor
enum SyntheticPaster {
    /// How long to wait for the target to become frontmost before giving up.
    private static let timeout = Duration.seconds(1)
    private static let pollInterval = Duration.milliseconds(20)
    /// `kVK_ANSI_V`. On layouts where that key isn't V (e.g. Dvorak) the paste is a different
    /// shortcut; the value is still on the clipboard.
    private static let vKey: CGKeyCode = 9

    static func paste(into target: PasteTarget) {
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else { return }
        // With the popover, Colorsip is active and has to hand activation over.
        NSApp.yieldActivation(to: app)
        app.activate()
        Task {
            let clock = ContinuousClock()
            let deadline = clock.now + timeout
            while NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid {
                guard clock.now < deadline else { return }
                try? await Task.sleep(for: pollInterval)
            }
            postCommandV()
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
