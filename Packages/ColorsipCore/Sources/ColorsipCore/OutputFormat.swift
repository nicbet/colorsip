import Foundation

/// An output format for copy, paste and the loupe label (`spec.md` §5.3), in display order.
public enum OutputFormat: String, Sendable, CaseIterable, Identifiable, Codable {
    case cssHex, cssHexNoHash, cssRGB, cssHSL, cssOKLCH, cssDisplayP3
    case swiftUI, nsColor, uiColor, android, androidXML

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
        case .androidXML: "Android (XML)"
        }
    }

    /// `color` written in this format. Formats that can't express the color's gamut get it
    /// gamut-mapped (sRGB for Hex, RGB, HSL and Android; Display P3 for Display P3). Numbers are
    /// rounded to about 8-bit precision; the stored color is never changed.
    public func string(for color: CSipColor) -> String {
        switch self {
        case .cssHex:
            return color.hex
        case .cssHexNoHash:
            return String(color.hex.dropFirst())
        case .cssRGB:
            let rgb = color.gamutMapped(to: .srgb).components.map { Self.number($0 * 255, decimals: 0) }
            return "rgb(\(rgb.joined(separator: " "))\(Self.cssAlpha(color.alpha)))"
        case .cssHSL:
            let hsl = color.gamutMapped(to: .hsl).components
            let h = Self.hue(hsl[0], decimals: 2)
            let s = Self.number(hsl[1], decimals: 2)
            let l = Self.number(hsl[2], decimals: 2)
            return "hsl(\(h) \(s)% \(l)%\(Self.cssAlpha(color.alpha)))"
        case .cssOKLCH:
            let lch = color.converted(to: .oklch).components
            let l = Self.number(lch[0] * 100, decimals: 1)
            let c = Self.number(lch[1], decimals: 3)
            let h = Self.hue(lch[2], decimals: 1)
            return "oklch(\(l)% \(c) \(h)\(Self.cssAlpha(color.alpha)))"
        case .cssDisplayP3:
            let p3 = color.gamutMapped(to: .displayP3).components.map { Self.number($0, decimals: 3) }
            return "color(display-p3 \(p3.joined(separator: " "))\(Self.cssAlpha(color.alpha)))"
        case .swiftUI, .nsColor, .uiColor:
            return appleCode(for: color)
        case .android, .androidXML:
            let bytes = [CSipColor.byte(color.alpha)]
                + color.gamutMapped(to: .srgb).components.map(CSipColor.byte)
            let hex = bytes.map { String(format: "%02X", $0) }.joined()
            return (self == .android ? "0x" : "#") + hex
        }
    }

    /// SwiftUI, NSColor or UIColor code. Colors stored in sRGB, HSL or HWB use sRGB; all others use
    /// Display P3, so wide-gamut colors survive.
    private func appleCode(for color: CSipColor) -> String {
        let usesSRGB = [.srgb, .hsl, .hwb].contains(color.colorSpace)
        let rgb = color.gamutMapped(to: usesSRGB ? .srgb : .displayP3).components
            .map { Self.number($0, decimals: 3) }
        let alpha = Self.number(color.alpha, decimals: 3)
        let (r, g, b) = (rgb[0], rgb[1], rgb[2])
        switch self {
        case .swiftUI:
            let space = usesSRGB ? ".sRGB" : ".displayP3"
            return "Color(\(space), red: \(r), green: \(g), blue: \(b), opacity: \(alpha))"
        case .nsColor:
            let red = usesSRGB ? "srgbRed" : "displayP3Red"
            return "NSColor(\(red): \(r), green: \(g), blue: \(b), alpha: \(alpha))"
        default:
            let red = usesSRGB ? "red" : "displayP3Red"
            return "UIColor(\(red): \(r), green: \(g), blue: \(b), alpha: \(alpha))"
        }
    }

    /// The CSS alpha suffix, ` / 80%`, or nothing when alpha rounds to 100%.
    private static func cssAlpha(_ alpha: Double) -> String {
        let percent = rounded(alpha * 100, decimals: 1)
        return percent >= 100 ? "" : " / \(number(percent, decimals: 1))%"
    }

    /// A hue in 0..<360 after rounding, so 359.996 is written as 0.
    private static func hue(_ degrees: Double, decimals: Int) -> String {
        let h = rounded(Conversion.normalizedHue(degrees), decimals: decimals)
        return number(h >= 360 ? 0 : h, decimals: decimals)
    }

    /// `value` rounded to at most `decimals` places, without trailing zeros or `-0`, and always
    /// with `.` as the decimal separator.
    static func number(_ value: Double, decimals: Int) -> String {
        var string = String(format: "%.\(decimals)f", rounded(value, decimals: decimals))
        if string.contains(".") {
            while string.hasSuffix("0") { string.removeLast() }
            if string.hasSuffix(".") { string.removeLast() }
        }
        return string
    }

    private static func rounded(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10, Double(decimals))
        let r = (value * factor).rounded() / factor
        return r == 0 ? 0 : r  // drops the sign of -0
    }
}

extension CSipColor {
    /// This color written in `format`. See ``OutputFormat/string(for:)``.
    public func formatted(as format: OutputFormat) -> String {
        format.string(for: self)
    }
}
