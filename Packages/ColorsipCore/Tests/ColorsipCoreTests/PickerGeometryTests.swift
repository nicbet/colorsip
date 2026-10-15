import CoreGraphics
import Testing
@testable import ColorsipCore

/// A 2× built-in display at the origin and a 1× external display to its right, top-aligned.
let builtIn = PickerDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
let external = PickerDisplay(id: 2, frame: CGRect(x: 1512, y: -98, width: 1920, height: 1080), scale: 1)

@Suite("Picker geometry")
struct PickerGeometryTests {
    @Test func pixelSize() {
        #expect(builtIn.pixelWidth == 3024)
        #expect(builtIn.pixelHeight == 1964)
        #expect(external.pixelWidth == 1920)
    }

    @Test func displayAtPoint() {
        let displays = [builtIn, external]
        #expect(PickerGeometry.display(at: CGPoint(x: 10, y: 10), in: displays) == builtIn)
        #expect(PickerGeometry.display(at: CGPoint(x: 1512, y: 10), in: displays) == external)
        // Max edges are exclusive.
        #expect(PickerGeometry.display(at: CGPoint(x: 1511.9, y: 981.9), in: displays) == builtIn)
        // The gap under the built-in display that the taller external one doesn't cover.
        #expect(PickerGeometry.display(at: CGPoint(x: 100, y: -50), in: displays) == nil)
    }

    @Test func pixelAtPointIsTopLeftOriginInPixels() {
        // Top-left corner of the built-in display.
        #expect(PickerGeometry.pixel(at: CGPoint(x: 0, y: 981.9), on: builtIn) == PixelPoint(x: 0, y: 0))
        // Half a point is one pixel on a 2× display.
        #expect(PickerGeometry.pixel(at: CGPoint(x: 10.5, y: 981), on: builtIn) == PixelPoint(x: 21, y: 2))
        #expect(PickerGeometry.pixel(at: CGPoint(x: 1512 + 100.7, y: 982 - 10.2), on: external)
            == PixelPoint(x: 100, y: 10))
    }

    @Test func pixelAtPointIsClampedIntoTheDisplay() {
        #expect(PickerGeometry.pixel(at: CGPoint(x: 1512, y: 0), on: builtIn) == PixelPoint(x: 3023, y: 1963))
        #expect(PickerGeometry.pixel(at: CGPoint(x: -5, y: 2000), on: builtIn) == PixelPoint(x: 0, y: 0))
    }

    @Test func pointOfPixelIsItsCenter() {
        #expect(PickerGeometry.point(of: PixelPoint(x: 21, y: 2), on: builtIn) == CGPoint(x: 10.75, y: 980.75))
        #expect(PickerGeometry.point(of: PixelPoint(x: 100, y: 10), on: external) == CGPoint(x: 1612.5, y: 971.5))
    }

    @Test func pointAndPixelRoundTrip() {
        for pixel in [PixelPoint(x: 0, y: 0), PixelPoint(x: 3023, y: 1963), PixelPoint(x: 777, y: 1234)] {
            #expect(PickerGeometry.pixel(at: PickerGeometry.point(of: pixel, on: builtIn), on: builtIn) == pixel)
        }
    }

    @Test func movingStepsPhysicalPixels() {
        let start = CGPoint(x: 10.6, y: 980.9)  // pixel (21, 2)
        let right = PickerGeometry.moved(start, dx: 1, dy: 0, on: builtIn)
        #expect(PickerGeometry.pixel(at: right, on: builtIn) == PixelPoint(x: 22, y: 2))
        #expect(right == CGPoint(x: 11.25, y: 980.75))
        let down = PickerGeometry.moved(start, dx: 0, dy: 10, on: builtIn)
        #expect(PickerGeometry.pixel(at: down, on: builtIn) == PixelPoint(x: 21, y: 12))
        let left = PickerGeometry.moved(CGPoint(x: 1612.5, y: 971.5), dx: -1, dy: 0, on: external)
        #expect(left == CGPoint(x: 1611.5, y: 971.5))
    }

    @Test func movingStopsAtTheDisplayEdge() {
        let corner = PickerGeometry.point(of: PixelPoint(x: 3, y: 1960), on: builtIn)
        let moved = PickerGeometry.moved(corner, dx: -10, dy: 10, on: builtIn)
        #expect(PickerGeometry.pixel(at: moved, on: builtIn) == PixelPoint(x: 0, y: 1963))
        #expect(PickerGeometry.display(at: moved, in: [builtIn, external]) == builtIn)
    }
}

@Suite("Pixel grid")
struct PixelGridTests {
    @Test func cellsAroundTheCenterRowByRow() {
        let grid = PixelGrid(center: PixelPoint(x: 10, y: 20), size: 3, pixelWidth: 100, pixelHeight: 100)
        #expect(grid.cells == [
            PixelPoint(x: 9, y: 19), PixelPoint(x: 10, y: 19), PixelPoint(x: 11, y: 19),
            PixelPoint(x: 9, y: 20), PixelPoint(x: 10, y: 20), PixelPoint(x: 11, y: 20),
            PixelPoint(x: 9, y: 21), PixelPoint(x: 10, y: 21), PixelPoint(x: 11, y: 21),
        ])
        #expect(grid.centerIndex == 4)
    }

    @Test func cellsOutsideTheDisplayAreEmpty() {
        let grid = PixelGrid(center: PixelPoint(x: 0, y: 99), size: 3, pixelWidth: 100, pixelHeight: 100)
        #expect(grid.cells == [
            nil, PixelPoint(x: 0, y: 98), PixelPoint(x: 1, y: 98),
            nil, PixelPoint(x: 0, y: 99), PixelPoint(x: 1, y: 99),
            nil, nil, nil,
        ])
        #expect(grid.cells[grid.centerIndex] == PixelPoint(x: 0, y: 99))
    }
}

/// `value` as IEEE half-float bits, rounded to nearest: what a half-float capture contains.
func halfBits(_ value: Double) -> UInt16 {
    let f = Float(value)
    let bits = f.bitPattern
    let sign = UInt16((bits >> 16) & 0x8000)
    if f == 0 { return sign }
    let exponent = Int((bits >> 23) & 0xff) - 127 + 15
    var mantissa = bits & 0x7f_ffff
    if exponent <= 0 {
        guard exponent >= -10 else { return sign }
        mantissa |= 0x80_0000
        let shift = UInt32(14 - exponent)
        var half = mantissa >> shift
        if (mantissa >> (shift - 1)) & 1 == 1 { half += 1 }
        return sign | UInt16(half)
    }
    var half = UInt32(exponent) << 10 | (mantissa >> 13)
    if mantissa & 0x1000 != 0 { half += 1 }
    return sign | UInt16(half)
}

private func littleEndian16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xff), UInt8(value >> 8)] }
private func littleEndian32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xff) } }

private func sample(_ grid: PixelGrid, _ bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int, format: CapturePixelFormat) -> [PixelSample?] {
    bytes.withUnsafeBytes { PixelSampler.sample(grid, bytes: $0, width: width, height: height, bytesPerRow: bytesPerRow, format: format) }
}

@Suite("Pixel sampler")
struct PixelSamplerTests {
    @Test func decodesHalfFloats() {
        #expect(PixelSampler.half(0x3c00) == 1)
        #expect(PixelSampler.half(0x0000) == 0)
        #expect(PixelSampler.half(0xbc00) == -1)
        #expect(PixelSampler.half(0x3800) == 0.5)
        #expect(PixelSampler.half(0x0001) == 0x1p-24)  // Smallest subnormal.
        #expect(PixelSampler.half(0x7bff) == 65504)
        for value in [0.0, 1, -0.25, 0.331, 1.0 / 255, 0.9, 1.5, 0.00002] {
            #expect(abs(PixelSampler.half(halfBits(value)) - value) <= abs(value) / 2048 + 0x1p-25)
        }
    }

    /// A 2×2 image with row padding; pixel (x, y) is (x, y, -0.5, 1).
    @Test func readsHalfFloatRowsWithPadding() {
        var bytes: [UInt8] = []
        for y in 0..<2 {
            for x in 0..<2 { bytes += [Double(x), Double(y), -0.5, 1].flatMap { littleEndian16(halfBits($0)) } }
            bytes += [UInt8](repeating: 0, count: 8)
        }
        let grid = PixelGrid(center: PixelPoint(x: 1, y: 1), size: 3, pixelWidth: 2, pixelHeight: 2)
        #expect(sample(grid, bytes, width: 2, height: 2, bytesPerRow: 24, format: .rgbaHalf) == [
            PixelSample(red: 0, green: 0, blue: -0.5, alpha: 1), PixelSample(red: 1, green: 0, blue: -0.5, alpha: 1), nil,
            PixelSample(red: 0, green: 1, blue: -0.5, alpha: 1), PixelSample(red: 1, green: 1, blue: -0.5, alpha: 1), nil,
            nil, nil, nil,
        ])
    }

    @Test func readsTenBitARGB() {
        // A 3, R 1023, G 512, B 0.
        let word: UInt32 = 3 << 30 | 1023 << 20 | 512 << 10 | 0
        let grid = PixelGrid(center: PixelPoint(x: 0, y: 0), size: 1, pixelWidth: 1, pixelHeight: 1)
        #expect(sample(grid, littleEndian32(word), width: 1, height: 1, bytesPerRow: 4, format: .argb2101010)
            == [PixelSample(red: 1, green: 512.0 / 1023, blue: 0, alpha: 1)])
    }

    @Test func readsBGRA() {
        let grid = PixelGrid(center: PixelPoint(x: 1, y: 0), size: 1, pixelWidth: 2, pixelHeight: 1)
        let bytes: [UInt8] = [0, 0, 0, 0, 51, 102, 255, 255]
        #expect(sample(grid, bytes, width: 2, height: 1, bytesPerRow: 8, format: .bgra8)
            == [PixelSample(red: 1, green: 0.4, blue: 0.2, alpha: 1)])
    }

    @Test func cellsOutsideTheImageAreEmpty() {
        // The capture can be smaller than the display while it changes resolution.
        let grid = PixelGrid(center: PixelPoint(x: 4, y: 0), size: 1, pixelWidth: 10, pixelHeight: 10)
        #expect(sample(grid, [UInt8](repeating: 0, count: 64), width: 4, height: 2, bytesPerRow: 32, format: .rgbaHalf) == [nil])
    }
}

@Suite("Capture color")
struct CaptureColorTests {
    let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    @Test func displayP3SampleKeepsItsValues() throws {
        let color = try #require(CaptureColor.color(PixelSample(red: 0.236, green: 0.235, blue: 0.859, alpha: 1), in: p3))
        #expect(color.colorSpace == .displayP3)
        for (a, b) in zip(color.components, [0.236, 0.235, 0.859]) {
            #expect(abs(a - b) < 1e-5)
        }
        #expect(color.alpha == 1)
    }

    @Test func linearSampleIsEncoded() throws {
        let linear = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        let color = try #require(CaptureColor.color(PixelSample(red: 0.214, green: 0, blue: 1, alpha: 1), in: linear))
        #expect(abs(color.components[0] - 0.5) < 1e-3)
        #expect(abs(color.components[2] - 1) < 1e-5)
    }

    @Test func valuesOutsideP3AreNotClipped() throws {
        let extendedSRGB = try #require(CGColorSpace(name: CGColorSpace.extendedSRGB))
        // sRGB −1 is linear −1: far more negative red than P3's wider red primary can absorb.
        let color = try #require(CaptureColor.color(PixelSample(red: -1, green: 1, blue: 0, alpha: 1), in: extendedSRGB))
        #expect(color.components[0] < -0.1)
    }

    /// Why the picker captures linear half floats: 8-bit sRGB content comes back with the exact same
    /// hex. Gamma-encoded half floats don't manage that near black (e.g. #03d200 → #04d200).
    @Test func sRGBBytesRoundTripThroughLinearHalfFloatP3() throws {
        let linearP3 = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        let values = Array(stride(from: 0, through: 255, by: 15)) + [1, 2, 3, 60, 122, 157, 219, 224, 253, 254]
        var wrong: [String] = []
        for r in values {
            for g in values {
                for b in values {
                    let source = CSipColor(.srgb, Double(r) / 255, Double(g) / 255, Double(b) / 255)
                    let c = source.converted(to: .displayP3).components
                        .map { PixelSampler.half(halfBits(RGBSpace.displayP3.decode($0))) }
                    let picked = try #require(
                        CaptureColor.color(PixelSample(red: c[0], green: c[1], blue: c[2], alpha: 1), in: linearP3))
                    if picked.hex != source.hex { wrong.append("\(source.hex) → \(picked.hex)") }
                }
            }
        }
        #expect(wrong.isEmpty, "\(wrong.count) differ, e.g. \(wrong.prefix(5))")
    }
}

@Suite("Picker windows")
struct PickerWindowTests {
    private let front = PickerWindow(frame: CGRect(x: 50, y: 50, width: 100, height: 100), bundleID: "front")
    private let back = PickerWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400), bundleID: "back")

    @Test func theFirstWindowContainingThePointWins() {
        let windows = [front, back]
        #expect(PickerGeometry.window(at: CGPoint(x: 100, y: 100), in: windows) == front)
        #expect(PickerGeometry.window(at: CGPoint(x: 10, y: 10), in: windows) == back)
    }

    @Test func noWindowAtThePoint() {
        #expect(PickerGeometry.window(at: CGPoint(x: 500, y: 10), in: [front, back]) == nil)
        #expect(PickerGeometry.window(at: .zero, in: []) == nil)
    }

    @Test func maxEdgesAreExclusive() {
        #expect(PickerGeometry.window(at: CGPoint(x: 150, y: 100), in: [front]) == nil)
        #expect(PickerGeometry.window(at: CGPoint(x: 50, y: 50), in: [front]) == front)
    }
}
