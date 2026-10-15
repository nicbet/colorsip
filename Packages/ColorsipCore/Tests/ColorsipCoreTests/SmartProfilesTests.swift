import Foundation
import Testing
@testable import ColorsipCore

@Suite("Target profile")
struct TargetProfileTests {
    @Test func mapsToColorSpaces() {
        #expect(TargetProfile.srgb.colorSpace == .srgb)
        #expect(TargetProfile.displayP3.colorSpace == .displayP3)
        #expect(TargetProfile.genericRGB.colorSpace == .genericRGB)
    }

    @Test func badges() {
        #expect(TargetProfile.allCases.map(\.badge) == ["sRGB", "P3", "Generic"])
    }

    @Test func rawValuesAreTheColorSpaceNames() {
        #expect(TargetProfile.allCases.map(\.rawValue) == ["srgb", "display-p3", "generic-rgb"])
    }
}

@Suite("Smart Profiles")
struct SmartProfilesTests {
    @Test func defaultsMapBrowsersAndFigmaToSRGBAndDesignToolsToP3() {
        let profiles = SmartProfiles()
        #expect(profiles.fallback == .srgb)
        for id in ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
                   "com.microsoft.edgemac", "com.brave.Browser", "com.figma.Desktop"] {
            #expect(profiles.profile(forBundleID: id) == .srgb, "\(id)")
        }
        for id in ["com.apple.dt.Xcode", "com.bohemiancoding.sketch3", "com.pixelmatorteam.pixelmator.x",
                   "com.apple.Preview"] {
            #expect(profiles.profile(forBundleID: id) == .displayP3, "\(id)")
        }
    }

    @Test func unlistedOrUnknownAppsUseTheFallback() {
        var profiles = SmartProfiles()
        profiles.fallback = .genericRGB
        #expect(profiles.profile(forBundleID: "com.example.Unknown") == .genericRGB)
        #expect(profiles.profile(forBundleID: nil) == .genericRGB)
    }

    @Test func bundleIDsMatchCaseInsensitively() {
        #expect(SmartProfiles().profile(forBundleID: "COM.APPLE.DT.XCODE") == .displayP3)
    }

    @Test func setRuleAddsAtTheEnd() {
        var profiles = SmartProfiles(rules: [], fallback: .srgb)
        profiles.setRule(bundleID: "com.a", name: "A", profile: .displayP3)
        profiles.setRule(bundleID: "com.b", name: "B", profile: .genericRGB)
        #expect(profiles.rules.map(\.bundleID) == ["com.a", "com.b"])
        #expect(profiles.profile(forBundleID: "com.b") == .genericRGB)
    }

    @Test func setRuleForAListedAppUpdatesItInPlace() {
        var profiles = SmartProfiles()
        let index = profiles.rules.firstIndex { $0.bundleID == "com.apple.Safari" }
        profiles.setRule(bundleID: "com.apple.safari", name: "Safari", profile: .displayP3)
        #expect(profiles.rules.count == SmartProfiles.defaultRules.count)
        #expect(profiles.rules.firstIndex { $0.bundleID == "com.apple.Safari" } == index)
        #expect(profiles.profile(forBundleID: "com.apple.Safari") == .displayP3)
    }

    @Test func removeRule() {
        var profiles = SmartProfiles()
        profiles.removeRule(bundleID: "com.figma.Desktop")
        #expect(!profiles.rules.contains { $0.bundleID == "com.figma.Desktop" })
        profiles.fallback = .displayP3
        #expect(profiles.profile(forBundleID: "com.figma.Desktop") == .displayP3)
    }

    @Test func restoreDefaultsKeepsTheFallback() {
        var profiles = SmartProfiles(rules: [], fallback: .genericRGB)
        profiles.restoreDefaults()
        #expect(profiles.rules == SmartProfiles.defaultRules)
        #expect(profiles.fallback == .genericRGB)
    }

    @Test func roundTripKeepsRemovedDefaultsRemoved() throws {
        var profiles = SmartProfiles()
        profiles.removeRule(bundleID: "com.apple.Preview")
        profiles.setRule(bundleID: "com.example.Paint", name: "Paint", profile: .genericRGB)
        profiles.fallback = .displayP3
        let decoded = try JSONDecoder.library.decode(SmartProfiles.self, from: JSONEncoder.library.encode(profiles))
        #expect(decoded == profiles)
    }

    @Test func encodesRulesAndFallback() throws {
        let profiles = SmartProfiles(rules: [ProfileRule(bundleID: "com.a", name: "A", profile: .displayP3)], fallback: .srgb)
        let json = String(decoding: try JSONEncoder.library.encode(profiles), as: UTF8.self)
        #expect(json.contains(#""bundleID" : "com.a""#))
        #expect(json.contains(#""profile" : "display-p3""#))
        #expect(json.contains(#""fallback" : "srgb""#))
    }

    @Test func decodingIsLenient() throws {
        let json = #"""
            { "fallback": "display-native",
              "rules": [
                { "bundleID": "com.a", "name": "A", "profile": "display-p3" },
                { "bundleID": "com.b", "name": "B", "profile": "adobe-rgb" },
                { "name": "No ID", "profile": "srgb" },
                { "bundleID": "com.c", "profile": "generic-rgb" }
              ] }
            """#
        let profiles = try JSONDecoder.library.decode(SmartProfiles.self, from: Data(json.utf8))
        #expect(profiles.fallback == .srgb)
        #expect(profiles.rules == [
            ProfileRule(bundleID: "com.a", name: "A", profile: .displayP3),
            ProfileRule(bundleID: "com.c", name: "com.c", profile: .genericRGB),
        ])
    }

    @Test func missingRulesGiveTheDefaults() throws {
        let profiles = try JSONDecoder.library.decode(SmartProfiles.self, from: Data(#"{ "fallback": "generic-rgb" }"#.utf8))
        #expect(profiles.rules == SmartProfiles.defaultRules)
        #expect(profiles.fallback == .genericRGB)
    }

    @Test func duplicateRulesKeepTheFirst() throws {
        let json = #"""
            { "rules": [
                { "bundleID": "com.a", "name": "A", "profile": "display-p3" },
                { "bundleID": "COM.A", "name": "A2", "profile": "srgb" }
            ] }
            """#
        let profiles = try JSONDecoder.library.decode(SmartProfiles.self, from: Data(json.utf8))
        #expect(profiles.rules == [ProfileRule(bundleID: "com.a", name: "A", profile: .displayP3)])
    }
}
