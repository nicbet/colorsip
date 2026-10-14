import Observation

/// Registration state of the app's login item, mirroring `SMAppService.Status`.
public enum LoginItemStatus: Sendable {
    case notRegistered, enabled, requiresApproval, notFound
}

/// The system service that registers the app as a login item. The app adapts
/// `SMAppService.mainApp`; tests use a fake.
@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Launch at login (`spec.md` §1). Off by default: nothing is registered until the user turns it
/// on. State is always re-read from the service, so it matches the system even after a failure.
@MainActor
@Observable
public final class LaunchAtLogin {
    public private(set) var status: LoginItemStatus
    public private(set) var lastError: (any Error)?

    private let service: any LoginItemService

    public init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    /// On once registered, including while waiting for the user's approval in System Settings.
    public var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// The user has to allow Colorsip in System Settings → General → Login Items.
    public var requiresApproval: Bool { status == .requiresApproval }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            lastError = nil
        } catch {
            lastError = error
        }
        refresh()
    }

    /// Re-reads the status, for example after the user changed it in System Settings.
    public func refresh() {
        status = service.status
    }
}
