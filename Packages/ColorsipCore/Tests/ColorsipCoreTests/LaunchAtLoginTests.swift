import Testing
@testable import ColorsipCore

@MainActor
final class FakeLoginItemService: LoginItemService {
    struct Failure: Error {}

    var status: LoginItemStatus
    /// Status the service reports after a successful `register()`.
    var statusAfterRegister: LoginItemStatus = .enabled
    var failNextCall = false
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if failNextCall { failNextCall = false; throw Failure() }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCalls += 1
        if failNextCall { failNextCall = false; throw Failure() }
        status = .notRegistered
    }
}

@Suite("Launch at login")
@MainActor
struct LaunchAtLoginTests {
    @Test func offByDefaultAndRegistersNothing() {
        let service = FakeLoginItemService()
        let model = LaunchAtLogin(service: service)
        #expect(!model.isEnabled)
        #expect(!model.requiresApproval)
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
    }

    @Test func reflectsAnExistingRegistration() {
        #expect(LaunchAtLogin(service: FakeLoginItemService(status: .enabled)).isEnabled)
    }

    @Test func enableRegisters() {
        let service = FakeLoginItemService()
        let model = LaunchAtLogin(service: service)
        model.setEnabled(true)
        #expect(service.registerCalls == 1)
        #expect(model.isEnabled)
        #expect(model.lastError == nil)
    }

    @Test func disableUnregisters() {
        let service = FakeLoginItemService(status: .enabled)
        let model = LaunchAtLogin(service: service)
        model.setEnabled(false)
        #expect(service.unregisterCalls == 1)
        #expect(!model.isEnabled)
    }

    @Test func requiresApprovalCountsAsEnabled() {
        let service = FakeLoginItemService()
        service.statusAfterRegister = .requiresApproval
        let model = LaunchAtLogin(service: service)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.requiresApproval)
    }

    @Test func failedRegisterKeepsErrorAndRealState() {
        let service = FakeLoginItemService()
        service.failNextCall = true
        let model = LaunchAtLogin(service: service)
        model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.lastError != nil)
    }

    @Test func failedUnregisterKeepsErrorAndRealState() {
        let service = FakeLoginItemService(status: .enabled)
        service.failNextCall = true
        let model = LaunchAtLogin(service: service)
        model.setEnabled(false)
        #expect(model.isEnabled)
        #expect(model.lastError != nil)
    }

    @Test func successClearsAPreviousError() {
        let service = FakeLoginItemService()
        service.failNextCall = true
        let model = LaunchAtLogin(service: service)
        model.setEnabled(true)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.lastError == nil)
    }

    @Test func refreshPicksUpOutsideChanges() {
        let service = FakeLoginItemService()
        let model = LaunchAtLogin(service: service)
        service.status = .enabled // e.g. toggled in System Settings
        model.refresh()
        #expect(model.isEnabled)
    }
}
