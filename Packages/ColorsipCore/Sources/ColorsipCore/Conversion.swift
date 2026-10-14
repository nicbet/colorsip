import Foundation

/// The conversion math. Every space converts through CIE XYZ with a D65 white point, except for
/// shortcuts between sRGB, HSL and HWB, and between OKLab and OKLCH. Matrices follow CSS Color 4;
/// inverses are computed rather than hard-coded, so round trips are exact to rounding error.
enum Conversion {
    static func convert(_ c: Vector3, from source: ColorSpace, to target: ColorSpace) -> Vector3 {
        if source == target { return c }
        switch (source, target) {
        case (.srgb, .hsl), (.srgb, .hwb), (.hsl, _), (.hwb, _):
            return fromSRGB(toSRGB(c, from: source), to: target)
        case (.oklab, .oklch): return oklabToOKLCH(c)
        case (.oklch, .oklab): return oklchToOKLab(c)
        default: return fromXYZ(toXYZ(c, from: source), to: target)
        }
    }

    // MARK: XYZ hub

    static func toXYZ(_ c: Vector3, from space: ColorSpace) -> Vector3 {
        switch space {
        case .srgb, .displayP3, .genericRGB:
            let rgb = RGBSpace(space)!
            return rgb.toXYZ * c.map(rgb.decode)
        case .hsl, .hwb: return toXYZ(toSRGB(c, from: space), from: .srgb)
        case .oklab: return oklabToXYZ(c)
        case .oklch: return oklabToXYZ(oklchToOKLab(c))
        }
    }

    static func fromXYZ(_ xyz: Vector3, to space: ColorSpace) -> Vector3 {
        switch space {
        case .srgb, .displayP3, .genericRGB:
            let rgb = RGBSpace(space)!
            return (rgb.fromXYZ * xyz).map(rgb.encode)
        case .hsl, .hwb: return fromSRGB(fromXYZ(xyz, to: .srgb), to: space)
        case .oklab: return xyzToOKLab(xyz)
        case .oklch: return oklabToOKLCH(xyzToOKLab(xyz))
        }
    }

    // MARK: OKLab / OKLCH

    static let xyzToLMS = Matrix3(
        0.8190224379967030, 0.3619062600528904, -0.1288737815209879,
        0.0329836539323885, 0.9292868615863434, 0.0361446663506424,
        0.0481771893596242, 0.2642395317527308, 0.6335478284694309)
    static let lmsToOKLab = Matrix3(
        0.2104542683093140, 0.7936177747023054, -0.0040720430116193,
        1.9779985324311684, -2.4285922420485799, 0.4505937096174110,
        0.0259040424655478, 0.7827717124575296, -0.8086757548809640)
    static let lmsToXYZ = xyzToLMS.inverse
    static let oklabToLMS = lmsToOKLab.inverse

    static func xyzToOKLab(_ xyz: Vector3) -> Vector3 {
        lmsToOKLab * (xyzToLMS * xyz).map(cbrt)
    }

    static func oklabToXYZ(_ lab: Vector3) -> Vector3 {
        lmsToXYZ * (oklabToLMS * lab).map { $0 * $0 * $0 }
    }

    /// Below this chroma the hue is noise, and is stored as 0.
    static let achromaticChroma = 1e-7

    static func oklabToOKLCH(_ lab: Vector3) -> Vector3 {
        let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
        let hue = chroma < achromaticChroma ? 0 : normalizedHue(atan2(lab.z, lab.y) * 180 / .pi)
        return Vector3(lab.x, chroma, hue)
    }

    static func oklchToOKLab(_ lch: Vector3) -> Vector3 {
        let radians = lch.z * .pi / 180
        return Vector3(lch.x, lch.y * cos(radians), lch.y * sin(radians))
    }

    // MARK: HSL / HWB (CSS Color 4, sRGB based)

    static func toSRGB(_ c: Vector3, from space: ColorSpace) -> Vector3 {
        switch space {
        case .hsl: return hslToSRGB(c)
        case .hwb: return hwbToSRGB(c)
        default: return convert(c, from: space, to: .srgb)
        }
    }

    static func fromSRGB(_ rgb: Vector3, to space: ColorSpace) -> Vector3 {
        switch space {
        case .hsl: return srgbToHSL(rgb)
        case .hwb: return srgbToHWB(rgb)
        default: return convert(rgb, from: .srgb, to: space)
        }
    }

    /// The hue in degrees of an RGB triple, shared by HSL, HWB and HSB. 0 for grays.
    static func hue(_ rgb: Vector3) -> Double {
        let (r, g, b) = (rgb.x, rgb.y, rgb.z)
        let mx = max(r, g, b)
        let d = mx - min(r, g, b)
        guard d != 0 else { return 0 }
        let sector: Double =
            if mx == r { (g - b) / d + (g < b ? 6 : 0) }
            else if mx == g { (b - r) / d + 2 }
            else { (r - g) / d + 4 }
        return normalizedHue(sector * 60)
    }

    static func srgbToHSL(_ rgb: Vector3) -> Vector3 {
        let mx = max(rgb.x, rgb.y, rgb.z)
        let mn = min(rgb.x, rgb.y, rgb.z)
        let l = (mx + mn) / 2
        var h = hue(rgb)
        var s = mx == mn || l == 0 || l == 1 ? 0 : (mx - l) / min(l, 1 - l)
        // Out-of-gamut input can give a negative saturation: flip the hue instead.
        if s < 0 {
            h = normalizedHue(h + 180)
            s = -s
        }
        return Vector3(h, s * 100, l * 100)
    }

    static func hslToSRGB(_ hsl: Vector3) -> Vector3 {
        let s = hsl.y / 100
        let l = hsl.z / 100
        let a = s * min(l, 1 - l)
        func channel(_ n: Double) -> Double {
            let k = (n + normalizedHue(hsl.x) / 30).truncatingRemainder(dividingBy: 12)
            return l - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return Vector3(channel(0), channel(8), channel(4))
    }

    static func srgbToHWB(_ rgb: Vector3) -> Vector3 {
        Vector3(hue(rgb), min(rgb.x, rgb.y, rgb.z) * 100, (1 - max(rgb.x, rgb.y, rgb.z)) * 100)
    }

    static func hwbToSRGB(_ hwb: Vector3) -> Vector3 {
        let w = hwb.y / 100
        let b = hwb.z / 100
        if w + b >= 1 {
            let gray = w / (w + b)
            return Vector3(gray, gray, gray)
        }
        return hslToSRGB(Vector3(hwb.x, 100, 50)).map { $0 * (1 - w - b) + w }
    }

    static func normalizedHue(_ degrees: Double) -> Double {
        let h = degrees.truncatingRemainder(dividingBy: 360)
        return h < 0 ? h + 360 : h
    }
}

// MARK: - RGB spaces

/// An RGB space: primaries and transfer function, with a D65 white point.
struct RGBSpace: Sendable {
    let colorSpace: ColorSpace
    let toXYZ: Matrix3
    let fromXYZ: Matrix3
    let decode: @Sendable (Double) -> Double
    let encode: @Sendable (Double) -> Double

    static let srgb = RGBSpace(
        .srgb, red: (0.640, 0.330), green: (0.300, 0.600), blue: (0.150, 0.060),
        decode: srgbDecode, encode: srgbEncode)
    static let displayP3 = RGBSpace(
        .displayP3, red: (0.680, 0.320), green: (0.265, 0.690), blue: (0.150, 0.060),
        decode: srgbDecode, encode: srgbEncode)
    /// Matches `/System/Library/ColorSync/Profiles/Generic RGB Profile.icc`.
    static let genericRGB = RGBSpace(
        .genericRGB, red: (0.630, 0.340), green: (0.295, 0.605), blue: (0.155, 0.077),
        decode: { gammaDecode($0, 1.8) }, encode: { gammaEncode($0, 1.8) })

    init?(_ space: ColorSpace) {
        switch space {
        case .srgb: self = .srgb
        case .displayP3: self = .displayP3
        case .genericRGB: self = .genericRGB
        default: return nil
        }
    }

    private init(
        _ colorSpace: ColorSpace,
        red: (Double, Double), green: (Double, Double), blue: (Double, Double),
        decode: @escaping @Sendable (Double) -> Double,
        encode: @escaping @Sendable (Double) -> Double
    ) {
        func xyz(_ xy: (Double, Double)) -> Vector3 {
            Vector3(xy.0 / xy.1, 1, (1 - xy.0 - xy.1) / xy.1)
        }
        let r = xyz(red), g = xyz(green), b = xyz(blue)
        let primaries = Matrix3(r.x, g.x, b.x, r.y, g.y, b.y, r.z, g.z, b.z)
        let scale = primaries.inverse * xyz(Self.whiteD65)
        let m = Matrix3(
            r.x * scale.x, g.x * scale.y, b.x * scale.z,
            r.y * scale.x, g.y * scale.y, b.y * scale.z,
            r.z * scale.x, g.z * scale.y, b.z * scale.z)
        self.colorSpace = colorSpace
        self.toXYZ = m
        self.fromXYZ = m.inverse
        self.decode = decode
        self.encode = encode
    }

    static let whiteD65 = (0.3127, 0.3290)

    // Transfer functions extend to negative values by symmetry, as in CSS Color 4.

    @Sendable static func srgbDecode(_ v: Double) -> Double {
        let a = abs(v)
        let linear = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
        return v < 0 ? -linear : linear
    }

    @Sendable static func srgbEncode(_ v: Double) -> Double {
        let a = abs(v)
        let encoded = a > 0.0031308 ? 1.055 * pow(a, 1 / 2.4) - 0.055 : 12.92 * a
        return v < 0 ? -encoded : encoded
    }

    static func gammaDecode(_ v: Double, _ gamma: Double) -> Double {
        v < 0 ? -pow(-v, gamma) : pow(v, gamma)
    }

    static func gammaEncode(_ v: Double, _ gamma: Double) -> Double {
        v < 0 ? -pow(-v, 1 / gamma) : pow(v, 1 / gamma)
    }
}

// MARK: - Linear algebra

struct Vector3: Sendable, Equatable {
    var x, y, z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    func map(_ f: (Double) -> Double) -> Vector3 { Vector3(f(x), f(y), f(z)) }

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    /// Whether every component is within 0–1, allowing for rounding error.
    var isInUnitCube: Bool {
        let epsilon = 1e-6
        return [x, y, z].allSatisfy { $0 >= -epsilon && $0 <= 1 + epsilon }
    }

    static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
}

/// A row-major 3×3 matrix.
struct Matrix3: Sendable {
    var m: [Double]

    init(_ m: Double...) {
        precondition(m.count == 9)
        self.m = m
    }

    static func * (a: Matrix3, v: Vector3) -> Vector3 {
        let m = a.m
        return Vector3(
            m[0] * v.x + m[1] * v.y + m[2] * v.z,
            m[3] * v.x + m[4] * v.y + m[5] * v.z,
            m[6] * v.x + m[7] * v.y + m[8] * v.z)
    }

    var inverse: Matrix3 {
        let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        return Matrix3(
            (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
            (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
            (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det)
    }
}
