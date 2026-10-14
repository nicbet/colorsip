import AppKit
import Carbon.HIToolbox
import ColorsipCore
import SwiftUI

/// Shows an action's shortcut and records a new one: click, then press the combination.
/// Esc cancels, ⌫ clears. Global shortcuts are suspended while recording, so pressing the current
/// one is captured instead of triggering it.
struct ShortcutRecorder: View {
    let action: ShortcutAction
    let manager: ShortcutManager

    @State private var isRecording = false
    @State private var monitor: Any?
    /// Why the last recorded shortcut was rejected.
    @State private var rejection: ShortcutProblem?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                if manager.shortcut(for: action) != action.defaultShortcut {
                    Button("Restore Default") {
                        rejection = manager.restoreDefault(for: action)
                    }
                    .buttonStyle(.link)
                }
                Button(action: { isRecording ? stop() : start() }) {
                    Text(label)
                        .foregroundStyle(isRecording || manager.shortcut(for: action) == nil ? .secondary : .primary)
                        .frame(minWidth: 110)
                }
            }
            if let problem = rejection ?? manager.problems[action] {
                Text(problem.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private var label: String {
        if isRecording { return "Type Shortcut…" }
        return manager.shortcut(for: action)?.displayString(keyName: keyName(for:)) ?? "None"
    }

    private func start() {
        rejection = nil
        isRecording = true
        manager.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        manager.resume()
    }

    /// Returns `nil` to swallow the key press, or the event to let it through.
    private func record(_ event: NSEvent) -> NSEvent? {
        let shortcut = KeyboardShortcut(
            keyCode: event.keyCode, modifiers: .init(cocoaFlags: event.modifierFlags.rawValue))
        switch (Int(shortcut.keyCode), shortcut.modifiers) {
        case (kVK_Tab, _):
            return event // keep keyboard navigation working
        case (kVK_Escape, []):
            break
        case (kVK_Delete, []), (kVK_ForwardDelete, []):
            rejection = manager.set(nil, for: action)
        default:
            rejection = manager.set(shortcut, for: action)
        }
        stop()
        return nil
    }
}

extension ShortcutAction {
    var title: String {
        switch self {
        case .picker: "Pick a color"
        case .contrastChecker: "Open contrast checker"
        case .mainWindow: "Open main window"
        }
    }
}

extension ShortcutProblem {
    var message: String {
        switch self {
        case .needsModifier: "Use at least one of ⌘, ⌃ or ⌥."
        case .usedBy(let action): "Already used by “\(action.title)”."
        case .reservedBySystem: "Used by macOS."
        case .inUseByAnotherApp: "Another app is using this shortcut."
        }
    }
}
