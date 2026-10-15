import CoreGraphics

/// A display the picker covers (`spec.md` §4.2).
public struct PickerDisplay: Equatable, Sendable {
    /// The `CGDirectDisplayID`.
    public var id: UInt32
    /// In global points, AppKit coordinates: origin at the bottom left of the primary display, y up.
    public var frame: CGRect
    /// Pixels per point.
    public var scale: Double

    public init(id: UInt32, frame: CGRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }

    public var pixelWidth: Int { Int((frame.width * scale).rounded()) }
    public var pixelHeight: Int { Int((frame.height * scale).rounded()) }
}

/// An on-screen window of another app, for Smart Profiles (`spec.md` §6).
public struct PickerWindow: Equatable, Sendable {
    /// In global points, AppKit coordinates, like ``PickerDisplay/frame``.
    public var frame: CGRect
    /// The owning app's bundle ID, if it has one.
    public var bundleID: String?

    public init(frame: CGRect, bundleID: String?) {
        self.frame = frame
        self.bundleID = bundleID
    }
}

/// A physical pixel of a display, with the origin at the top left and y down: the layout of a
/// screen capture.
public struct PixelPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Converts between global points and the physical pixels of each display.
public enum PickerGeometry {
    /// The display whose frame contains `point` (max edges exclusive), or `nil` in a gap between
    /// displays.
    public static func display(at point: CGPoint, in displays: [PickerDisplay]) -> PickerDisplay? {
        displays.first { point.x >= $0.frame.minX && point.x < $0.frame.maxX && point.y >= $0.frame.minY && point.y < $0.frame.maxY }
    }

    /// The first window of `windows`, ordered front to back, that contains `point` (max edges
    /// exclusive).
    public static func window(at point: CGPoint, in windows: [PickerWindow]) -> PickerWindow? {
        windows.first { point.x >= $0.frame.minX && point.x < $0.frame.maxX && point.y >= $0.frame.minY && point.y < $0.frame.maxY }
    }

    /// The pixel of `display` under `point`, clamped into the display.
    public static func pixel(at point: CGPoint, on display: PickerDisplay) -> PixelPoint {
        let x = Int(((point.x - display.frame.minX) * display.scale).rounded(.down))
        let y = Int(((display.frame.maxY - point.y) * display.scale).rounded(.down))
        return PixelPoint(x: min(max(x, 0), display.pixelWidth - 1), y: min(max(y, 0), display.pixelHeight - 1))
    }

    /// The center of `pixel` in global points.
    public static func point(of pixel: PixelPoint, on display: PickerDisplay) -> CGPoint {
        CGPoint(
            x: display.frame.minX + (Double(pixel.x) + 0.5) / display.scale,
            y: display.frame.maxY - (Double(pixel.y) + 0.5) / display.scale)
    }

    /// The center of the pixel `dx` right and `dy` down from the one under `point`. It stops at the
    /// edges of `display`, so it never moves to another display.
    public static func moved(_ point: CGPoint, dx: Int, dy: Int, on display: PickerDisplay) -> CGPoint {
        let current = pixel(at: point, on: display)
        let target = PixelPoint(
            x: min(max(current.x + dx, 0), display.pixelWidth - 1),
            y: min(max(current.y + dy, 0), display.pixelHeight - 1))
        return self.point(of: target, on: display)
    }
}

/// The `size × size` pixels the loupe magnifies, around `center`, row by row from the top left.
/// Cells outside the display are `nil`, so the center cell is always the pointer's pixel.
public struct PixelGrid: Equatable, Sendable {
    public let center: PixelPoint
    /// Pixels across; odd.
    public let size: Int
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(center: PixelPoint, size: Int, pixelWidth: Int, pixelHeight: Int) {
        self.center = center
        self.size = size
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var centerIndex: Int { size * size / 2 }

    public var cells: [PixelPoint?] {
        let radius = size / 2
        return (-radius...radius).flatMap { dy in
            (-radius...radius).map { dx -> PixelPoint? in
                let x = center.x + dx
                let y = center.y + dy
                guard x >= 0, x < pixelWidth, y >= 0, y < pixelHeight else { return nil }
                return PixelPoint(x: x, y: y)
            }
        }
    }
}

/// One captured pixel, in the frame's color space. Float formats can hold values outside 0–1.
public struct PixelSample: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// The pixel formats the picker captures in (`spec.md` §4.2), most precise first.
public enum CapturePixelFormat: CaseIterable, Sendable {
    /// `kCVPixelFormatType_64RGBAHalf`: four little-endian half floats.
    case rgbaHalf
    /// `kCVPixelFormatType_ARGB2101010LEPacked` (`l10r`): a little-endian 32-bit word with A in
    /// bits 30–31, R in 20–29, G in 10–19 and B in 0–9.
    case argb2101010
    /// `kCVPixelFormatType_32BGRA`.
    case bgra8

    var bytesPerPixel: Int { self == .rgbaHalf ? 8 : 4 }
}

/// Reads a grid's pixels from a screen capture.
public enum PixelSampler {
    /// The colors of `grid`'s cells in an image of `format`. Cells outside the grid's display or
    /// the image are `nil`.
    public static func sample(
        _ grid: PixelGrid, bytes: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
        format: CapturePixelFormat
    ) -> [PixelSample?] {
        grid.cells.map { cell in
            guard let cell, cell.x < width, cell.y < height else { return nil }
            let offset = cell.y * bytesPerRow + cell.x * format.bytesPerPixel
            guard offset + format.bytesPerPixel <= bytes.count else { return nil }
            return pixel(at: offset, in: bytes, format: format)
        }
    }

    private static func pixel(at offset: Int, in bytes: UnsafeRawBufferPointer, format: CapturePixelFormat) -> PixelSample {
        switch format {
        case .rgbaHalf:
            let c = (0..<4).map { i in half(UInt16(bytes[offset + 2 * i]) | UInt16(bytes[offset + 2 * i + 1]) << 8) }
            return PixelSample(red: c[0], green: c[1], blue: c[2], alpha: c[3])
        case .argb2101010:
            let word = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
            func channel(_ shift: UInt32) -> Double { Double((word >> shift) & 0x3ff) / 1023 }
            return PixelSample(red: channel(20), green: channel(10), blue: channel(0), alpha: Double(word >> 30) / 3)
        case .bgra8:
            func channel(_ i: Int) -> Double { Double(bytes[offset + i]) / 255 }
            return PixelSample(red: channel(2), green: channel(1), blue: channel(0), alpha: channel(3))
        }
    }

    /// An IEEE half float. Decoded by hand because `Float16` isn't available on x86_64 macOS.
    static func half(_ bits: UInt16) -> Double {
        let sign: FloatingPointSign = bits & 0x8000 == 0 ? .plus : .minus
        let exponent = Int((bits >> 10) & 0x1f)
        let mantissa = Double(bits & 0x3ff)
        switch exponent {
        case 0: return Double(sign: sign, exponent: -24, significand: mantissa)
        case 0x1f: return mantissa == 0 ? Double(sign: sign, exponent: 0, significand: .infinity) : .nan
        default: return Double(sign: sign, exponent: exponent - 15, significand: 1 + mantissa / 1024)
        }
    }
}

/// Converts captured samples into the picker's working space.
public enum CaptureColor {
    private static let extendedDisplayP3 = CGColorSpace(name: CGColorSpace.extendedDisplayP3)!

    /// `sample` in `space` as a Display P3 color, through ColorSync. Values outside Display P3 are
    /// kept outside 0–1 rather than clipped.
    public static func color(_ sample: PixelSample, in space: CGColorSpace) -> CSipColor? {
        let components = [sample.red, sample.green, sample.blue, sample.alpha].map { CGFloat($0) }
        guard let captured = CGColor(colorSpace: space, components: components),
            let p3 = captured.converted(to: extendedDisplayP3, intent: .defaultIntent, options: nil),
            let c = p3.components, c.count == 4
        else { return nil }
        return CSipColor(.displayP3, Double(c[0]), Double(c[1]), Double(c[2]), alpha: Double(c[3]))
    }
}
