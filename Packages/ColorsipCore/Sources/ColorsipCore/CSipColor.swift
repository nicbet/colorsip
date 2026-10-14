import Foundation

/// The color spaces a ``CSipColor`` can be stored in. Raw values are the CSS Color 4 / DTCG names.
/// See `spec.md` §5.1.
public enum ColorSpace: String, CaseIterable, Sendable, Codable {
    case srgb
    case displayP3 = "display-p3"
    /// Apple's "Generic RGB Profile" (gamma 1.8).
    case genericRGB = "generic-rgb"
    case oklab
    case oklch
    case hsl
    case hwb

    /// The RGB space whose gamut bounds this space, or `nil` for the unbounded OKLab/OKLCH.
    var gamutSpace: RGBSpace? {
        switch self {
        case .srgb, .hsl, .hwb: .srgb
        case .displayP3: .displayP3
        case .genericRGB: .genericRGB
        case .oklab, .oklch: nil
        }
    }
}

/// Hue, saturation and brightness for the color editor. Not a storage space: DTCG has no HSB.
/// Hue is 0–360, saturation and brightness are 0–1.
public struct HSB: Sendable, Hashable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double
    public var alpha: Double

    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
        self.alpha = alpha
    }
}

/// A color as stored: a color space, three 64-bit components and alpha, kept exactly as given.
///
/// Component conventions follow DTCG: RGB spaces use 0–1, OKLab/OKLCH use L 0–1, HSL and HWB use
/// 0–100 for their percentages, and hues are degrees. Values outside the usual ranges are allowed.
///
/// `==` and hashing are exact. Use ``isPerceptuallyEqual(to:threshold:)`` to de-duplicate.
public struct CSipColor: Sendable, Hashable {
    public var colorSpace: ColorSpace
    public var components: [Double]
    public var alpha: Double

    public init(_ space: ColorSpace, _ c0: Double, _ c1: Double, _ c2: Double, alpha: Double = 1) {
        colorSpace = space
        components = [c0, c1, c2]
        self.alpha = alpha
    }

    init(_ space: ColorSpace, _ c: Vector3, alpha: Double) {
        self.init(space, c.x, c.y, c.z, alpha: alpha)
    }

    var vector: Vector3 { Vector3(components[0], components[1], components[2]) }

    /// This color in `space`. Nothing is clamped, so out-of-gamut colors keep components outside
    /// the 0–1 range.
    public func converted(to space: ColorSpace) -> CSipColor {
        if space == colorSpace { return self }
        return CSipColor(space, Conversion.convert(vector, from: colorSpace, to: space), alpha: alpha)
    }

    /// The perceptual distance ΔEOK: the Euclidean distance in OKLab. Alpha is ignored.
    public func deltaEOK(_ other: CSipColor) -> Double {
        let a = converted(to: .oklab).vector
        let b = other.converted(to: .oklab).vector
        return (a - b).length
    }

    /// Whether the colors look the same: ΔEOK below `threshold` and the same alpha within 0.002.
    public func isPerceptuallyEqual(to other: CSipColor, threshold: Double = 0.002) -> Bool {
        deltaEOK(other) < threshold && abs(alpha - other.alpha) < 0.002
    }

    /// Whether the color fits in the gamut of `space`. OKLab and OKLCH have no gamut boundary.
    public func isInGamut(_ space: ColorSpace) -> Bool {
        guard let rgb = space.gamutSpace else { return true }
        return Conversion.convert(vector, from: colorSpace, to: rgb.colorSpace).isInUnitCube
    }

    /// The sRGB fallback, gamut-mapped: `#rrggbb`, or `#rrggbbaa` when alpha isn't opaque after
    /// rounding to 8 bits. Informative only, never read back as the source of truth.
    public var hex: String {
        let rgb = gamutMapped(to: .srgb).components
        var bytes = rgb.map(Self.byte)
        let alphaByte = Self.byte(alpha)
        if alphaByte != 255 { bytes.append(alphaByte) }
        return "#" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func byte(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }
}

// MARK: - HSB

extension CSipColor {
    /// A color built from editor HSB values in the RGB space `space` (sRGB, Display P3 or Generic
    /// RGB). The color is stored in `space`.
    public init(hsb: HSB, in space: ColorSpace = .srgb) {
        precondition(space.isRGB, "HSB needs an RGB space, not \(space)")
        func channel(_ n: Double) -> Double {
            let k = (n + hsb.hue / 60).truncatingRemainder(dividingBy: 6)
            let k6 = k < 0 ? k + 6 : k
            return hsb.brightness - hsb.brightness * hsb.saturation * max(0, min(k6, 4 - k6, 1))
        }
        self.init(space, channel(5), channel(3), channel(1), alpha: hsb.alpha)
    }

    /// This color as editor HSB values in the RGB space `space`.
    public func hsb(in space: ColorSpace = .srgb) -> HSB {
        precondition(space.isRGB, "HSB needs an RGB space, not \(space)")
        let rgb = converted(to: space).vector
        let mx = max(rgb.x, rgb.y, rgb.z)
        let mn = min(rgb.x, rgb.y, rgb.z)
        let saturation = mx == 0 ? 0 : (mx - mn) / mx
        return HSB(hue: Conversion.hue(rgb), saturation: saturation, brightness: mx, alpha: alpha)
    }
}

extension ColorSpace {
    var isRGB: Bool { self == .srgb || self == .displayP3 || self == .genericRGB }
}
