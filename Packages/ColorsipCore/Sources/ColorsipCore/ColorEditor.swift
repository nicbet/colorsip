import Foundation

/// The sets of numeric fields the color editor's model switcher offers (`spec.md` §5.4), in order.
public enum EditorModel: String, CaseIterable, Identifiable, Sendable {
    case hex, rgb, hsb, hsl, oklch, displayP3

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "RGB"
        case .hsb: "HSB"
        case .hsl: "HSL"
        case .oklch: "OKLCH"
        case .displayP3: "P3"
        }
    }

    public var fieldLabels: [String] {
        switch self {
        case .hex: ["HEX"]
        case .rgb, .displayP3: ["R", "G", "B"]
        case .hsb: ["H", "S", "B"]
        case .hsl: ["H", "S", "L"]
        case .oklch: ["L", "C", "H"]
        }
    }
}

/// The draft of the compact color editor (cs-722793): one swatch's color, name and description,
/// changed by the 2D field, the sliders, the numeric fields and the eyedropper. Nothing reaches the
/// library until the draft is saved with ``LibraryController/save(_:in:at:)``.
///
/// Edits are stored in the **working space**, an RGB space chosen from the swatch's color: sRGB for
/// sRGB, HSL and HWB colors, Generic RGB for Generic RGB, Display P3 otherwise. An edit that leaves
/// the working space's gamut promotes it to Display P3; beyond P3, components are kept unclamped.
/// An unchanged color keeps its own space and components.
public struct ColorEditor: Sendable, Equatable {
    public let original: Swatch
    /// The draft color.
    public private(set) var color: CSipColor
    public private(set) var workingSpace: ColorSpace
    /// What the 2D field and the hue slider show, in the working space. Kept apart from `color` so a
    /// gray or black doesn't lose its hue and saturation.
    public private(set) var hsb: HSB
    public private(set) var name: String
    public var description: String
    /// Whether the name is the color's automatic name and still follows the color.
    private var nameFollowsColor: Bool

    public init(swatch: Swatch) {
        original = swatch
        color = swatch.color
        workingSpace = Self.workingSpace(for: swatch.color.colorSpace)
        hsb = swatch.color.hsb(in: workingSpace)
        name = swatch.name
        description = swatch.description ?? ""
        nameFollowsColor = swatch.name == swatch.color.friendlyName
    }

    private static func workingSpace(for space: ColorSpace) -> ColorSpace {
        switch space {
        case .srgb, .hsl, .hwb: .srgb
        case .genericRGB: .genericRGB
        case .displayP3, .oklab, .oklch: .displayP3
        }
    }

    public var isColorChanged: Bool { color != original.color }

    public var hasChanges: Bool {
        isColorChanged || name != original.name || description != (original.description ?? "")
    }

    /// Whether the HEX, RGB and HSL fields show a gamut-mapped value.
    public var isOutsideSRGB: Bool { !color.isInGamut(.srgb) }

    // MARK: - Field and sliders

    /// Sets saturation and brightness, each clamped to 0–1.
    public mutating func setSaturation(_ saturation: Double, brightness: Double) {
        hsb.saturation = Self.clamp(saturation, 0...1)
        hsb.brightness = Self.clamp(brightness, 0...1)
        applyHSB()
    }

    /// Sets the hue in degrees, wrapped into 0..<360.
    public mutating func setHue(_ hue: Double) {
        hsb.hue = Conversion.normalizedHue(hue)
        applyHSB()
    }

    /// Sets alpha, clamped to 0–1.
    public mutating func setAlpha(_ alpha: Double) {
        var new = color.converted(to: workingSpace)
        new.alpha = Self.clamp(alpha, 0...1)
        hsb.alpha = new.alpha
        setColor(new, keepingHSB: true)
    }

    /// Replaces the color with a re-picked one.
    public mutating func setPicked(_ picked: CSipColor) {
        setColor(picked, keepingHSB: false)
    }

    private mutating func applyHSB() {
        setColor(CSipColor(hsb: hsb, in: workingSpace), keepingHSB: true)
    }

    // MARK: - Numeric fields

    /// The text of each field of `model`, rounded like the output formats. HEX, RGB and HSL show
    /// the gamut-mapped sRGB value.
    public func fields(_ model: EditorModel) -> [String] {
        let n = OutputFormat.number
        switch model {
        case .hex:
            let bytes = color.gamutMapped(to: .srgb).components.map(CSipColor.byte)
            return ["#" + bytes.map { String(format: "%02x", $0) }.joined()]
        case .rgb:
            return color.gamutMapped(to: .srgb).components.map { n($0 * 255, 0) }
        case .hsb:
            return [Self.hue(hsb.hue), n(hsb.saturation * 100, 1), n(hsb.brightness * 100, 1)]
        case .hsl:
            let c = color.gamutMapped(to: .hsl).components
            return [Self.hue(c[0]), n(c[1], 1), n(c[2], 1)]
        case .oklch:
            let c = color.converted(to: .oklch).components
            return [n(c[0] * 100, 1), n(c[1], 3), Self.hue(c[2])]
        case .displayP3:
            return color.gamutMapped(to: .displayP3).components.map { n($0, 3) }
        }
    }

    /// Alpha as a percentage.
    public var alphaField: String { OutputFormat.number(color.alpha * 100, decimals: 1) }

    /// Applies typed text to field `index` of `model`. Returns whether the color changed: text that
    /// matches the field, doesn't parse, or names no field changes nothing. Numbers are clamped to
    /// the field's range; hues wrap.
    @discardableResult
    public mutating func commit(_ text: String, field index: Int, of model: EditorModel) -> Bool {
        let shown = fields(model)
        guard shown.indices.contains(index), text.trimmingCharacters(in: .whitespaces) != shown[index]
        else { return false }
        let before = color

        if model == .hex {
            guard let (rgb, alpha) = Self.parseHex(text) else { return false }
            setColor(CSipColor(.srgb, rgb[0], rgb[1], rgb[2], alpha: alpha ?? color.alpha), keepingHSB: false)
            return color != before
        }
        guard let value = Self.parseNumber(text) else { return false }

        switch model {
        case .hex:
            return false
        case .rgb:
            var c = color.gamutMapped(to: .srgb).components
            c[index] = Self.clamp(value, 0...255) / 255
            setColor(CSipColor(.srgb, c[0], c[1], c[2], alpha: color.alpha), keepingHSB: false)
        case .hsb:
            switch index {
            case 0: hsb.hue = Conversion.normalizedHue(value)
            case 1: hsb.saturation = Self.clamp(value, 0...100) / 100
            default: hsb.brightness = Self.clamp(value, 0...100) / 100
            }
            applyHSB()
        case .hsl:
            var c = color.gamutMapped(to: .hsl).components
            c[index] = index == 0 ? Conversion.normalizedHue(value) : Self.clamp(value, 0...100)
            setColor(CSipColor(.hsl, c[0], c[1], c[2], alpha: color.alpha), keepingHSB: false)
        case .oklch:
            var c = color.converted(to: .oklch).components
            switch index {
            case 0: c[0] = Self.clamp(value, 0...100) / 100
            case 1: c[1] = Self.clamp(value, 0...0.4)
            default: c[2] = Conversion.normalizedHue(value)
            }
            setColor(CSipColor(.oklch, c[0], c[1], c[2], alpha: color.alpha), keepingHSB: false)
        case .displayP3:
            var c = color.gamutMapped(to: .displayP3).components
            c[index] = Self.clamp(value, 0...1)
            setColor(CSipColor(.displayP3, c[0], c[1], c[2], alpha: color.alpha), keepingHSB: false)
        }
        return color != before
    }

    /// Applies a typed alpha percentage. Returns whether the color changed.
    @discardableResult
    public mutating func commitAlpha(_ text: String) -> Bool {
        guard text.trimmingCharacters(in: .whitespaces) != alphaField, let value = Self.parseNumber(text)
        else { return false }
        let before = color
        setAlpha(value / 100)
        return color != before
    }

    // MARK: - Name, description, reset

    /// Sets the name as typed. From then on it no longer follows the color.
    public mutating func setName(_ name: String) {
        self.name = name
        nameFollowsColor = false
    }

    /// Back to the swatch as it was when the editor opened.
    public mutating func reset() {
        self = ColorEditor(swatch: original)
    }

    // MARK: - Helpers

    /// Stores `new` in the working space, promoting it to Display P3 if it leaves the gamut.
    private mutating func setColor(_ new: CSipColor, keepingHSB: Bool) {
        let promoted = workingSpace != .displayP3 && !new.isInGamut(workingSpace)
        if promoted { workingSpace = .displayP3 }
        color = new.converted(to: workingSpace)
        if !keepingHSB || promoted {
            var next = color.hsb(in: workingSpace)
            // A gray has no hue, and black no saturation either: keep what the editor had.
            if next.saturation == 0 || next.brightness == 0 { next.hue = hsb.hue }
            if next.brightness == 0 { next.saturation = hsb.saturation }
            hsb = next
        }
        if nameFollowsColor { name = color.friendlyName }
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// A hue rounded to 1 decimal in 0..<360.
    private static func hue(_ degrees: Double) -> String {
        let h = (Conversion.normalizedHue(degrees) * 10).rounded() / 10
        return OutputFormat.number(h >= 360 ? 0 : h, decimals: 1)
    }

    /// A number, optionally followed by `%` or `°`. A comma is taken as the decimal separator.
    static func parseNumber(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("%") || s.hasSuffix("°") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(s), value.isFinite else { return nil }
        return value
    }

    /// `rgb`, `rgba`, `rrggbb` or `rrggbbaa`, with or without `#`. Components are 0–1; alpha is
    /// `nil` when the text has none.
    static func parseHex(_ text: String) -> (rgb: [Double], alpha: Double?)? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard [3, 4, 6, 8].contains(s.count), s.allSatisfy(\.isHexDigit) else { return nil }
        if s.count <= 4 { s = String(s.flatMap { [$0, $0] }) }
        let bytes = stride(from: 0, to: s.count, by: 2).map { i -> Double in
            let start = s.index(s.startIndex, offsetBy: i)
            return Double(Int(s[start..<s.index(start, offsetBy: 2)], radix: 16)!) / 255
        }
        return (Array(bytes.prefix(3)), bytes.count == 4 ? bytes[3] : nil)
    }
}
