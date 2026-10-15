import Foundation

/// Sends one pick where `spec.md` §4.5 says, as soon as it is made: into Color History, to the front
/// of the pick target (one undoable step, see ``LibraryController/addPick(_:name:at:)``), and onto
/// the clipboard in `format`, so the last pick of a session is the one left there. Picks are named
/// after the color (§5.5).
@MainActor
public func routePick(
    _ color: CSipColor, format: OutputFormat, history: ColorHistoryController, library: LibraryController,
    clipboard: some Clipboard, at date: Date = .now
) {
    let name = color.friendlyName
    history.record(color, name: name, at: date)
    library.addPick(color, name: name, at: date)
    copyValue(of: color, as: format, to: clipboard)
}

// MARK: - Cmd+click paste (`spec.md` §4.5)

/// An app a Cmd+click pick can be pasted into.
public struct PasteTarget: Equatable, Sendable {
    public let pid: Int32
    public let bundleID: String?

    public init(pid: Int32, bundleID: String?) {
        self.pid = pid
        self.bundleID = bundleID
    }
}

/// Remembers the app that was active before Colorsip, so a picker opened from the popover pastes
/// there rather than into Colorsip.
public struct PasteTargetTracker: Sendable {
    private let ownBundleID: String?
    private var lastOther: PasteTarget?

    public init(ownBundleID: String?) {
        self.ownBundleID = ownBundleID
    }

    /// Call for every app activation.
    public mutating func activated(_ app: PasteTarget) {
        if !isOwn(app) { lastOther = app }
    }

    /// The app to paste into: `frontmost` unless it is Colorsip, otherwise the last other app
    /// activated, if any.
    public func target(frontmost: PasteTarget?) -> PasteTarget? {
        if let frontmost, !isOwn(frontmost) { return frontmost }
        return lastOther
    }

    private func isOwn(_ app: PasteTarget) -> Bool {
        app.bundleID != nil && app.bundleID == ownBundleID
    }
}

/// What to do after a Cmd+click pick was routed.
public enum PastePlan: Equatable, Sendable {
    /// Activate the target and send Cmd+V.
    case paste(PasteTarget)
    /// No app to paste into: the value is only copied.
    case copyOnly
    /// The value is only copied; point the user to the Accessibility permission.
    case needsAccessibility
}

/// Routes a Cmd+click pick like ``routePick(_:format:history:library:clipboard:at:)``, copying it in
/// the format `formatForApp` chooses for the target's bundle ID (the hook for Smart Formats,
/// `spec.md` §13), and says whether it can be pasted.
@MainActor
public func routePastePick(
    _ color: CSipColor, into target: PasteTarget?, accessibilityGranted: Bool,
    formatForApp: (String?) -> OutputFormat, history: ColorHistoryController, library: LibraryController,
    clipboard: some Clipboard, at date: Date = .now
) -> PastePlan {
    routePick(
        color, format: formatForApp(target?.bundleID), history: history, library: library, clipboard: clipboard,
        at: date)
    guard let target else { return .copyOnly }
    return accessibilityGranted ? .paste(target) : .needsAccessibility
}
