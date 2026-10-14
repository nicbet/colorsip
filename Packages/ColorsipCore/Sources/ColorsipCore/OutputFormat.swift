/// An output format for copy, paste and the loupe label (`spec.md` §5.3), in display order.
public enum OutputFormat: String, Sendable, CaseIterable, Identifiable {
    case cssHex, cssHexNoHash, cssRGB, cssHSL, cssOKLCH, cssDisplayP3
    case swiftUI, nsColor, uiColor, android

    public static let `default`: OutputFormat = .cssHex

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .cssHex: "CSS Hex"
        case .cssHexNoHash: "CSS Hex (no #)"
        case .cssRGB: "CSS RGB"
        case .cssHSL: "CSS HSL"
        case .cssOKLCH: "CSS OKLCH"
        case .cssDisplayP3: "CSS Display P3"
        case .swiftUI: "SwiftUI"
        case .nsColor: "NSColor"
        case .uiColor: "UIColor"
        case .android: "Android"
        }
    }
}
