import Foundation
import Observation
import Synchronization
import Testing
@testable import ColorsipCore

@MainActor
final class FakePermissionChecker: PermissionChecker {
    var granted: Set<Permission>

    init(granted: Set<Permission> = []) {
        self.granted = granted
    }

    func isGranted(_ permission: Permission) -> Bool {
        granted.contains(permission)
    }
}

/// `LocalSettings` on a throwaway defaults suite.
final class TemporaryDefaults {
    let suite = "ColorsipTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    var localSettings: LocalSettings { LocalSettings(defaults: defaults) }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite("Permissions")
@MainActor
struct PermissionsTests {
    let temp: TemporaryDefaults

    init() throws {
        temp = try TemporaryDefaults()
    }

    private func permissions(granted: Set<Permission> = []) -> (Permissions, FakePermissionChecker) {
        let checker = FakePermissionChecker(granted: granted)
        return (Permissions(checker: checker, localSettings: temp.localSettings), checker)
    }

    @Test func onlyAccessibilityIsSkippable() {
        #expect(!Permission.screenRecording.isSkippable)
        #expect(Permission.accessibility.isSkippable)
    }

    @Test func missingIsInChecklistOrder() {
        #expect(permissions().0.missing == [.screenRecording, .accessibility])
        #expect(permissions(granted: [.screenRecording]).0.missing == [.accessibility])
        #expect(permissions(granted: Set(Permission.allCases)).0.missing.isEmpty)
    }

    @Test func refreshPicksUpGrants() {
        let (permissions, checker) = permissions()
        #expect(!permissions.isGranted(.screenRecording))
        checker.granted = [.screenRecording]
        #expect(!permissions.isGranted(.screenRecording)) // cached until refreshed
        permissions.refresh()
        #expect(permissions.isGranted(.screenRecording))
    }

    // MARK: Launch

    @Test func launchWithEverythingGrantedOpensNoChecklist() {
        let (permissions, _) = permissions(granted: Set(Permission.allCases))
        permissions.checkAtLaunch()
        #expect(permissions.checklist == nil)
    }

    @Test func launchListsEveryMissingPermissionAtOnce() throws {
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        let checklist = try #require(permissions.checklist)
        #expect(checklist.items == [.screenRecording, .accessibility])
        #expect(checklist.highlighted == nil)
        #expect(permissions.status(of: .screenRecording) == .missing)
        #expect(permissions.status(of: .accessibility) == .missing)
    }

    @Test func launchLeavesOutASkippedPermission() {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, _) = permissions(granted: [.screenRecording])
        permissions.checkAtLaunch()
        #expect(permissions.checklist == nil)
    }

    @Test func launchStillAsksForScreenRecordingWhenAccessibilityWasSkipped() throws {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        #expect(try #require(permissions.checklist).items == [.screenRecording])
    }

    @Test func aGrantedPermissionIsNoLongerRememberedAsSkipped() {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, checker) = permissions(granted: [.screenRecording])
        checker.granted = Set(Permission.allCases)
        permissions.refresh()
        #expect(temp.localSettings.skippedPermissions.isEmpty)
    }

    // MARK: Granting

    @Test func anyRowCanBeGrantedFirst() throws {
        let (permissions, checker) = permissions()
        permissions.checkAtLaunch()
        checker.granted = [.accessibility]
        permissions.refresh()
        #expect(try #require(permissions.checklist).items == [.screenRecording, .accessibility])
        #expect(permissions.status(of: .accessibility) == .granted)
        #expect(permissions.status(of: .screenRecording) == .missing)
        #expect(!permissions.isComplete)
    }

    @Test func grantingEveryRowCompletesTheChecklist() {
        let (permissions, checker) = permissions()
        permissions.checkAtLaunch()
        checker.granted = Set(Permission.allCases)
        permissions.refresh()
        #expect(permissions.checklist != nil)
        #expect(permissions.isComplete)
    }

    @Test func refreshWithoutChangesDoesntNotifyObservers() {
        // The checklist window observes `checklist` and the statuses, and polls every second.
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        let changed = Mutex(false)
        withObservationTracking {
            _ = permissions.checklist
            _ = permissions.isGranted(.screenRecording)
        } onChange: {
            changed.withLock { $0 = true }
        }
        permissions.refresh()
        #expect(!changed.withLock { $0 })
    }

    // MARK: Skipping

    @Test func screenRecordingCantBeSkipped() {
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        permissions.skip(.screenRecording)
        #expect(permissions.status(of: .screenRecording) == .missing)
        #expect(temp.localSettings.skippedPermissions.isEmpty)
    }

    @Test func skippingAccessibilityIsRememberedAndShown() {
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        permissions.skip(.accessibility)
        #expect(temp.localSettings.skippedPermissions == [.accessibility])
        #expect(permissions.status(of: .accessibility) == .skipped)
        #expect(!permissions.isComplete)
    }

    @Test func skippingEverythingWithNothingGrantedEndsTheChecklist() {
        let (permissions, _) = permissions(granted: [.screenRecording])
        permissions.checkAtLaunch()
        permissions.skip(.accessibility)
        #expect(permissions.checklist == nil)
    }

    @Test func skippingTheLastOpenRowAfterAGrantCompletes() {
        let (permissions, checker) = permissions()
        permissions.checkAtLaunch()
        checker.granted = [.screenRecording]
        permissions.refresh()
        permissions.skip(.accessibility)
        #expect(permissions.checklist != nil)
        #expect(permissions.isComplete)
    }

    @Test func aSkippedRowCanStillBeGranted() {
        let (permissions, checker) = permissions()
        permissions.checkAtLaunch()
        permissions.skip(.accessibility)
        checker.granted = [.accessibility]
        permissions.refresh()
        #expect(permissions.status(of: .accessibility) == .granted)
        #expect(temp.localSettings.skippedPermissions.isEmpty)
    }

    @Test func closingIsNotSkipping() {
        let (permissions, _) = permissions(granted: [.screenRecording])
        permissions.checkAtLaunch()
        permissions.closeGuide()
        #expect(permissions.checklist == nil)
        #expect(temp.localSettings.skippedPermissions.isEmpty)
    }

    // MARK: Starting again and requiring

    @Test func startingAgainIncludesSkippedPermissions() throws {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, _) = permissions(granted: [.screenRecording])
        #expect(permissions.startGuide())
        #expect(try #require(permissions.checklist).items == [.accessibility])
        // The skip is still remembered, but the new checklist offers the row again.
        #expect(permissions.status(of: .accessibility) == .missing)
    }

    @Test func startingWithNothingMissingOpensNoChecklist() {
        let (permissions, _) = permissions(granted: Set(Permission.allCases))
        #expect(!permissions.startGuide())
        #expect(permissions.checklist == nil)
    }

    @Test func requireAGrantedPermissionPasses() {
        let (permissions, _) = permissions(granted: [.screenRecording])
        #expect(permissions.require(.screenRecording))
        #expect(permissions.checklist == nil)
    }

    @Test func requireRechecksBeforeDeciding() {
        let (permissions, checker) = permissions()
        checker.granted = [.screenRecording]
        #expect(permissions.require(.screenRecording))
    }

    @Test func requireAMissingPermissionHighlightsItsRow() throws {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, _) = permissions()
        #expect(!permissions.require(.accessibility))
        let checklist = try #require(permissions.checklist)
        #expect(checklist.items == [.screenRecording, .accessibility])
        #expect(checklist.highlighted == .accessibility)
    }
}

@Suite("Screen Recording probe")
struct ScreenRecordingProbeTests {
    private let ownPID: Int32 = 100

    private func window(pid: Int32 = 200, name: String?, layer: Int = 0) -> WindowListEntry {
        WindowListEntry(ownerPID: pid, name: name, layer: layer)
    }

    @Test func anotherAppsWindowTitleMeansGranted() {
        let windows = [window(name: "Screen & System Audio Recording")]
        #expect(ScreenRecordingProbe.isGranted(windows: windows, ownPID: ownPID))
    }

    @Test func noVisibleTitlesMeansNotGranted() {
        // Without the permission, macOS leaves out other apps' window names.
        let windows = [window(name: nil), window(pid: 300, name: nil)]
        #expect(!ScreenRecordingProbe.isGranted(windows: windows, ownPID: ownPID))
    }

    @Test func ownWindowsDontCount() {
        let windows = [window(pid: ownPID, name: "Colorsip Permissions")]
        #expect(!ScreenRecordingProbe.isGranted(windows: windows, ownPID: ownPID))
    }

    @Test func emptyTitlesDontCount() {
        #expect(!ScreenRecordingProbe.isGranted(windows: [window(name: "")], ownPID: ownPID))
    }

    @Test func onlyNormalWindowsCount() {
        // The Dock, menu bar and status items are on other layers and may expose names anyway.
        let windows = [window(name: "Dock", layer: 20), window(name: "Item-0", layer: 25)]
        #expect(!ScreenRecordingProbe.isGranted(windows: windows, ownPID: ownPID))
    }
}
