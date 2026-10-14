import AppKit
import ApplicationServices
import ColorsipCore
import CoreGraphics

/// Reads and requests the TCC permissions behind `Permission`.
@MainActor
final class SystemPermissionChecker: PermissionChecker {
    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// Adds Colorsip to the permission's list in System Settings, so the user only has to turn it
    /// on. macOS may show its own prompt the first time.
    func register(_ permission: Permission) {
        switch permission {
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .accessibility:
            // The key's global is a mutable C var, which Swift 6 won't read from here.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    /// Opens the permission's pane in System Settings ▸ Privacy & Security.
    func openSettings(for permission: Permission) {
        let anchor = switch permission {
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
