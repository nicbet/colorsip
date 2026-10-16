import Foundation

/// A profile the picker converts samples to (`spec.md` §6). Raw values are the ``ColorSpace``
/// names.
public enum TargetProfile: String, CaseIterable, Sendable, Codable {
    case srgb
    /// The capture space: no conversion.
    case displayP3 = "display-p3"
    case genericRGB = "generic-rgb"

    public var colorSpace: ColorSpace {
        switch self {
        case .srgb: .srgb
        case .displayP3: .displayP3
        case .genericRGB: .genericRGB
        }
    }

    public var displayName: String {
        switch self {
        case .srgb: "sRGB IEC61966-2.1"
        case .displayP3: "Display P3"
        case .genericRGB: "Generic RGB"
        }
    }
}

/// One row of the Smart Profiles table: an app, by bundle ID, and its profile. `name` is only for
/// display.
public struct ProfileRule: Equatable, Sendable, Codable {
    public var bundleID: String
    public var name: String
    public var profile: TargetProfile

    public init(bundleID: String, name: String, profile: TargetProfile) {
        self.bundleID = bundleID
        self.name = name
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, name, profile
    }

    /// A missing name falls back to the bundle ID.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? bundleID
        profile = try container.decode(TargetProfile.self, forKey: .profile)
    }
}

/// The app → profile table and the fallback (`spec.md` §6), stored in full in `settings.json` so
/// a removed default stays removed:
///
/// ```json
/// "profiles": { "rules": [{ "bundleID": "com.apple.Safari", "name": "Safari", "profile": "srgb" }], "fallback": "srgb" }
/// ```
///
/// Bundle IDs match case-insensitively, as macOS treats them. The table holds each app once.
public struct SmartProfiles: Equatable, Sendable, Codable {
    public static let defaultRules: [ProfileRule] = [
        ProfileRule(bundleID: "com.apple.Safari", name: "Safari", profile: .srgb),
        ProfileRule(bundleID: "com.google.Chrome", name: "Google Chrome", profile: .srgb),
        ProfileRule(bundleID: "org.mozilla.firefox", name: "Firefox", profile: .srgb),
        ProfileRule(bundleID: "company.thebrowser.Browser", name: "Arc", profile: .srgb),
        ProfileRule(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", profile: .srgb),
        ProfileRule(bundleID: "com.brave.Browser", name: "Brave Browser", profile: .srgb),
        ProfileRule(bundleID: "com.figma.Desktop", name: "Figma", profile: .srgb),
        ProfileRule(bundleID: "com.apple.dt.Xcode", name: "Xcode", profile: .displayP3),
        ProfileRule(bundleID: "com.bohemiancoding.sketch3", name: "Sketch", profile: .displayP3),
        ProfileRule(bundleID: "com.pixelmatorteam.pixelmator.x", name: "Pixelmator Pro", profile: .displayP3),
        ProfileRule(bundleID: "com.apple.Preview", name: "Preview", profile: .displayP3),
    ]

    public private(set) var rules: [ProfileRule]
    /// The profile of apps without a rule, and of points over no window.
    public var fallback: TargetProfile

    public init(rules: [ProfileRule] = Self.defaultRules, fallback: TargetProfile = .srgb) {
        self.rules = []
        self.fallback = fallback
        for rule in rules where index(of: rule.bundleID) == nil {
            self.rules.append(rule)
        }
    }

    public func profile(forBundleID bundleID: String?) -> TargetProfile {
        bundleID.flatMap(index(of:)).map { rules[$0].profile } ?? fallback
    }

    /// Updates the app's row in place, or adds one at the end.
    public mutating func setRule(bundleID: String, name: String, profile: TargetProfile) {
        if let i = index(of: bundleID) {
            rules[i].profile = profile
        } else {
            rules.append(ProfileRule(bundleID: bundleID, name: name, profile: profile))
        }
    }

    public mutating func removeRule(bundleID: String) {
        if let i = index(of: bundleID) { rules.remove(at: i) }
    }

    /// Puts back the built-in rows; the fallback stays.
    public mutating func restoreDefaults() {
        rules = Self.defaultRules
    }

    private func index(of bundleID: String) -> Int? {
        rules.firstIndex { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    private enum CodingKeys: String, CodingKey {
        case rules, fallback
    }

    /// Missing rules give the defaults; unreadable rows are skipped; an unknown fallback is sRGB.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = (try? container.decodeIfPresent(TargetProfile.self, forKey: .fallback)) ?? .srgb
        guard var rows = try? container.nestedUnkeyedContainer(forKey: .rules) else {
            self.init(fallback: fallback)
            return
        }
        var rules: [ProfileRule] = []
        while !rows.isAtEnd {
            if let rule = try? rows.decode(ProfileRule.self) {
                rules.append(rule)
            } else {
                _ = try? rows.decode(Skip.self)
            }
        }
        self.init(rules: rules, fallback: fallback)
    }

    /// Consumes one array element of any shape: a failed decode doesn't advance the container.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) {}
    }
}
