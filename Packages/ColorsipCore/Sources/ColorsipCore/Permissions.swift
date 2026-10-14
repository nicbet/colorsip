import Observation

/// A macOS permission Colorsip asks for (`spec.md` §9), in checklist order.
public enum Permission: String, CaseIterable, Sendable {
    /// Needed by the picker.
    case screenRecording
    /// Only needed for Cmd+click paste.
    case accessibility

    /// Whether the checklist offers to skip it.
    public var isSkippable: Bool { self == .accessibility }
}

/// Reads whether a permission is granted. The app adapts `CGPreflightScreenCaptureAccess` and
/// `AXIsProcessTrusted`; tests use a fake.
@MainActor
public protocol PermissionChecker: AnyObject {
    func isGranted(_ permission: Permission) -> Bool
}

/// The onboarding checklist (`spec.md` §9): every listed permission at once, each with its own
/// live status.
public struct PermissionChecklist: Equatable, Sendable {
    /// The rows, in `Permission` order, fixed when the checklist starts.
    public let items: [Permission]
    /// The row of the feature that asked for its permission (`require`).
    public let highlighted: Permission?
    /// Rows skipped in this checklist.
    public internal(set) var skipped: Set<Permission> = []

    init(_ items: [Permission], highlighted: Permission? = nil) {
        self.items = items
        self.highlighted = highlighted
    }
}

/// A checklist row's status.
public enum PermissionStatus: Equatable, Sendable {
    case granted
    case skipped
    case missing
}

/// The status of each permission and the onboarding checklist (`spec.md` §9). Status is cached;
/// call `refresh()` to re-check it.
@MainActor
@Observable
public final class Permissions {
    public private(set) var checklist: PermissionChecklist?
    private var granted: Set<Permission> = []

    private let checker: any PermissionChecker
    @ObservationIgnored private let localSettings: LocalSettings

    public init(checker: any PermissionChecker, localSettings: LocalSettings) {
        self.checker = checker
        self.localSettings = localSettings
        refresh()
    }

    public func isGranted(_ permission: Permission) -> Bool {
        granted.contains(permission)
    }

    /// The permissions not granted, in checklist order.
    public var missing: [Permission] {
        Permission.allCases.filter { !granted.contains($0) }
    }

    /// A checklist row's status. A granted permission is granted even if it was skipped.
    public func status(of permission: Permission) -> PermissionStatus {
        if isGranted(permission) { return .granted }
        if checklist?.skipped.contains(permission) == true { return .skipped }
        return .missing
    }

    /// Whether every listed permission is granted or skipped.
    public var isComplete: Bool {
        checklist?.items.allSatisfy { status(of: $0) != .missing } ?? false
    }

    /// Re-checks every permission. Granted ones are no longer remembered as skipped.
    public func refresh() {
        // Polling runs every second; it must only notify the checklist window when something
        // changed. Assigning an equal set is quiet.
        let granted = Set(Permission.allCases.filter(checker.isGranted))
        self.granted = granted
        let skipped = localSettings.skippedPermissions
        if !skipped.isDisjoint(with: granted) {
            localSettings.skippedPermissions = skipped.subtracting(granted)
        }
    }

    /// Opens the checklist on the missing permissions the user hasn't skipped before.
    public func checkAtLaunch() {
        refresh()
        let skipped = localSettings.skippedPermissions
        let items = missing.filter { !skipped.contains($0) }
        checklist = items.isEmpty ? nil : PermissionChecklist(items)
    }

    /// Opens the checklist on every missing permission, skipped ones included, with `highlighted`
    /// (if it's missing) highlighted. Returns `false` if nothing is missing.
    @discardableResult
    public func startGuide(highlighting highlighted: Permission? = nil) -> Bool {
        refresh()
        let items = missing
        checklist = items.isEmpty ? nil : PermissionChecklist(
            items, highlighted: highlighted.flatMap { items.contains($0) ? $0 : nil }
        )
        return checklist != nil
    }

    /// For a feature that needs `permission`: `true` if it's granted, otherwise opens the
    /// checklist with it highlighted and returns `false`.
    public func require(_ permission: Permission) -> Bool {
        refresh()
        if isGranted(permission) { return true }
        startGuide(highlighting: permission)
        return false
    }

    /// Skips `permission`, if it can be skipped, and remembers that. If every row is then skipped
    /// and none granted, the checklist ends: there's no "all set" to show.
    public func skip(_ permission: Permission) {
        guard var checklist, permission.isSkippable, checklist.items.contains(permission),
              !isGranted(permission) else { return }
        localSettings.skippedPermissions.insert(permission)
        checklist.skipped.insert(permission)
        let allSkipped = checklist.items.allSatisfy(checklist.skipped.contains)
        self.checklist = allSkipped ? nil : checklist
    }

    /// Closes the checklist. This isn't skipping: the launch check asks again next time.
    public func closeGuide() {
        checklist = nil
    }
}
