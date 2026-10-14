import Testing
@testable import ColorsipCore

@Test func versionIsSet() {
    #expect(!ColorsipCore.version.isEmpty)
}
