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

    @Test func missingIsInGuideOrder() {
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

    @Test func launchWithEverythingGrantedStartsNoGuide() {
        let (permissions, _) = permissions(granted: Set(Permission.allCases))
        permissions.checkAtLaunch()
        #expect(permissions.guide == nil)
    }

    @Test func launchWalksThroughEveryMissingPermission() throws {
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        let guide = try #require(permissions.guide)
        #expect(guide.step == .permission(.screenRecording))
        #expect(guide.stepNumber == 1)
        #expect(guide.total == 2)
    }

    @Test func launchLeavesOutASkippedPermission() {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, _) = permissions(granted: [.screenRecording])
        permissions.checkAtLaunch()
        #expect(permissions.guide == nil)
    }

    @Test func launchStillAsksForScreenRecordingWhenAccessibilityWasSkipped() throws {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        let guide = try #require(permissions.guide)
        #expect(guide.pending == [.screenRecording])
    }

    @Test func aGrantedPermissionIsNoLongerRememberedAsSkipped() {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, checker) = permissions(granted: [.screenRecording])
        checker.granted = Set(Permission.allCases)
        permissions.refresh()
        #expect(temp.localSettings.skippedPermissions.isEmpty)
    }

    // MARK: Walking through

    @Test func grantingTheCurrentStepMovesOn() throws {
        let (permissions, checker) = permissions()
        permissions.checkAtLaunch()
        checker.granted = [.screenRecording]
        permissions.refresh()
        let guide = try #require(permissions.guide)
        #expect(guide.step == .permission(.accessibility))
        #expect(guide.stepNumber == 2)
    }

    @Test func grantingTheLastStepEndsOnDone() throws {
        let (permissions, checker) = permissions()
        permissions.checkAtLaunch()
        checker.granted = Set(Permission.allCases)
        permissions.refresh()
        #expect(try #require(permissions.guide).step == .done)
    }

    @Test func refreshWithoutChangesStaysOnTheStep() throws {
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        permissions.refresh()
        #expect(try #require(permissions.guide).step == .permission(.screenRecording))
    }

    @Test func refreshWithoutChangesDoesntNotifyObservers() {
        // The guide window observes `guide`, and the guide polls every second.
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        let changed = Mutex(false)
        withObservationTracking {
            _ = permissions.guide
            _ = permissions.isGranted(.screenRecording)
        } onChange: {
            changed.withLock { $0 = true }
        }
        permissions.refresh()
        #expect(!changed.withLock { $0 })
    }

    @Test func aLaterStepGrantedEarlyIsDropped() throws {
        let (permissions, checker) = permissions()
        permissions.checkAtLaunch()
        checker.granted = [.accessibility]
        permissions.refresh()
        let guide = try #require(permissions.guide)
        #expect(guide.pending == [.screenRecording])
        checker.granted = Set(Permission.allCases)
        permissions.refresh()
        #expect(try #require(permissions.guide).step == .done)
    }

    // MARK: Skipping

    @Test func screenRecordingCantBeSkipped() throws {
        let (permissions, _) = permissions()
        permissions.checkAtLaunch()
        permissions.skip()
        #expect(try #require(permissions.guide).step == .permission(.screenRecording))
        #expect(temp.localSettings.skippedPermissions.isEmpty)
    }

    @Test func skippingAccessibilityIsRemembered() {
        let (permissions, _) = permissions(granted: [.screenRecording])
        permissions.checkAtLaunch()
        permissions.skip()
        #expect(temp.localSettings.skippedPermissions == [.accessibility])
    }

    @Test func skippingTheOnlyStepEndsTheGuide() {
        let (permissions, _) = permissions(granted: [.screenRecording])
        permissions.checkAtLaunch()
        permissions.skip()
        #expect(permissions.guide == nil)
    }

    @Test func skippingAfterAGrantedStepEndsOnDone() throws {
        let (permissions, checker) = permissions()
        permissions.checkAtLaunch()
        checker.granted = [.screenRecording]
        permissions.refresh()
        permissions.skip()
        #expect(try #require(permissions.guide).step == .done)
    }

    @Test func closingIsNotSkipping() {
        let (permissions, _) = permissions(granted: [.screenRecording])
        permissions.checkAtLaunch()
        permissions.closeGuide()
        #expect(permissions.guide == nil)
        #expect(temp.localSettings.skippedPermissions.isEmpty)
    }

    // MARK: Starting again and requiring

    @Test func startingAgainIncludesSkippedPermissions() throws {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, _) = permissions(granted: [.screenRecording])
        #expect(permissions.startGuide())
        #expect(try #require(permissions.guide).pending == [.accessibility])
    }

    @Test func startingWithNothingMissingStartsNoGuide() {
        let (permissions, _) = permissions(granted: Set(Permission.allCases))
        #expect(!permissions.startGuide())
        #expect(permissions.guide == nil)
    }

    @Test func requireAGrantedPermissionPasses() {
        let (permissions, _) = permissions(granted: [.screenRecording])
        #expect(permissions.require(.screenRecording))
        #expect(permissions.guide == nil)
    }

    @Test func requireRechecksBeforeDeciding() {
        let (permissions, checker) = permissions()
        checker.granted = [.screenRecording]
        #expect(permissions.require(.screenRecording))
    }

    @Test func requireAMissingPermissionStartsTheGuideOnIt() throws {
        temp.localSettings.skippedPermissions = [.accessibility]
        let (permissions, _) = permissions()
        #expect(!permissions.require(.accessibility))
        let guide = try #require(permissions.guide)
        #expect(guide.pending == [.accessibility, .screenRecording])
        #expect(guide.step == .permission(.accessibility))
    }
}
