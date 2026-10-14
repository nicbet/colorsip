/// A window as `CGWindowListCopyWindowInfo` describes it, reduced to what the probe needs.
public struct WindowListEntry: Equatable, Sendable {
    public var ownerPID: Int32
    /// `kCGWindowName`. macOS leaves it out for other apps' windows without Screen Recording.
    public var name: String?
    /// `kCGWindowLayer`; 0 for normal app windows.
    public var layer: Int

    public init(ownerPID: Int32, name: String?, layer: Int) {
        self.ownerPID = ownerPID
        self.name = name
        self.layer = layer
    }
}

/// Detects a Screen Recording grant live. `CGPreflightScreenCaptureAccess` keeps its first answer
/// until the app restarts, but the window server checks the permission on every window list: it
/// only shows other apps' window titles when Colorsip has it. It never shows a system prompt.
public enum ScreenRecordingProbe {
    public static func isGranted(windows: [WindowListEntry], ownPID: Int32) -> Bool {
        // Only normal windows: the Dock, menu bar and status items may expose names regardless.
        windows.contains { window in
            window.ownerPID != ownPID && window.layer == 0 && !(window.name ?? "").isEmpty
        }
    }
}
