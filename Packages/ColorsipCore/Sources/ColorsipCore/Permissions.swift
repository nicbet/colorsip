import Observation

/// A macOS permission Colorsip asks for (`spec.md` §9), in the order the guide walks through them.
public enum Permission: String, CaseIterable, Sendable {
    /// Needed by the picker.
    case screenRecording
    /// Only needed for Cmd+click paste.
    case accessibility

    /// Whether the guide offers to skip it.
    public var isSkippable: Bool { self == .accessibility }
}

/// Reads whether a permission is granted. The app adapts `CGPreflightScreenCaptureAccess` and
/// `AXIsProcessTrusted`; tests use a fake.
@MainActor
public protocol PermissionChecker: AnyObject {
    func isGranted(_ permission: Permission) -> Bool
}

/// The onboarding guide's progress: the permissions it still has to walk through.
public struct PermissionGuide: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case permission(Permission)
        /// Everything that was asked for is granted or skipped.
        case done
    }

    /// The permissions still to go, the current one first.
    public internal(set) var pending: [Permission]
    /// The number of steps the guide started with.
    public let total: Int

    init(_ permissions: [Permission]) {
        pending = permissions
        total = permissions.count
    }

    public var step: Step { pending.first.map(Step.permission) ?? .done }

    /// The 1-based position of the current step.
    public var stepNumber: Int { total - pending.count + 1 }
}

/// The status of each permission and the onboarding guide (`spec.md` §9). Status is cached; call
/// `refresh()` to re-check it.
@MainActor
@Observable
public final class Permissions {
    public private(set) var guide: PermissionGuide?
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

    /// The permissions not granted, in guide order.
    public var missing: [Permission] {
        Permission.allCases.filter { !granted.contains($0) }
    }

    /// Re-checks every permission. The guide moves past the ones now granted, and they are no
    /// longer remembered as skipped.
    public func refresh() {
        let granted = Set(Permission.allCases.filter(checker.isGranted))
        // Polling runs every second; it must only notify the guide window when something changed.
        // Assigning an equal set is quiet, but mutating `guide` in place always notifies.
        self.granted = granted
        if var guide, guide.pending.contains(where: granted.contains) {
            guide.pending.removeAll(where: granted.contains)
            self.guide = guide
        }
        let skipped = localSettings.skippedPermissions
        if !skipped.isDisjoint(with: granted) {
            localSettings.skippedPermissions = skipped.subtracting(granted)
        }
    }

    /// Starts the guide for the missing permissions the user hasn't skipped before.
    public func checkAtLaunch() {
        refresh()
        let skipped = localSettings.skippedPermissions
        let steps = missing.filter { !skipped.contains($0) }
        guide = steps.isEmpty ? nil : PermissionGuide(steps)
    }

    /// Starts the guide for every missing permission, skipped ones included, with `first` (if
    /// it's missing) as the first step. Returns `false` if nothing is missing.
    @discardableResult
    public func startGuide(first: Permission? = nil) -> Bool {
        refresh()
        var steps = missing
        if let first, let index = steps.firstIndex(of: first) {
            steps.insert(steps.remove(at: index), at: 0)
        }
        guide = steps.isEmpty ? nil : PermissionGuide(steps)
        return guide != nil
    }

    /// For a feature that needs `permission`: `true` if it's granted, otherwise starts the guide
    /// on it and returns `false`.
    public func require(_ permission: Permission) -> Bool {
        refresh()
        if isGranted(permission) { return true }
        startGuide(first: permission)
        return false
    }

    /// Skips the current step, if it can be skipped, and remembers that. If it was the guide's
    /// only step, the guide ends: nothing was granted, so there's no "all set" step to show.
    public func skip() {
        guard var guide, case .permission(let permission) = guide.step, permission.isSkippable else {
            return
        }
        localSettings.skippedPermissions.insert(permission)
        guide.pending.removeFirst()
        self.guide = guide.total == 1 ? nil : guide
    }

    /// Closes the guide. This isn't skipping: the launch check asks again next time.
    public func closeGuide() {
        guide = nil
    }
}
