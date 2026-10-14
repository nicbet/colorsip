import Testing
@testable import ColorsipCore

@Suite("CSipColor storage")
struct ColorStorageTests {
    @Test func storesComponentsVerbatim() {
        let color = CSipColor(.displayP3, 0.123456789012345, -0.25, 1.75, alpha: 0.3333333333333333)
        #expect(color.colorSpace == .displayP3)
        #expect(color.components == [0.123456789012345, -0.25, 1.75])
        #expect(color.alpha == 0.3333333333333333)
    }

    @Test func alphaDefaultsToOpaque() {
        #expect(CSipColor(.srgb, 0, 0, 0).alpha == 1)
    }

    @Test func colorSpaceRawValuesMatchCSS() {
        #expect(ColorSpace.allCases.map(\.rawValue).sorted() == [
            "display-p3", "generic-rgb", "hsl", "hwb", "oklab", "oklch", "srgb",
        ])
    }

    @Test func swiftEqualityIsExact() {
        let a = CSipColor(.srgb, 0.5, 0.5, 0.5)
        #expect(a == CSipColor(.srgb, 0.5, 0.5, 0.5))
        #expect(a != CSipColor(.srgb, 0.5, 0.5, 0.5000001))
        #expect(a != CSipColor(.displayP3, 0.5, 0.5, 0.5))
    }

    @Test func conversionToSameSpaceIsIdentity() {
        let color = CSipColor(.srgb, 1.2, -0.1, 0.5, alpha: 0.4)
        #expect(color.converted(to: .srgb) == color)
    }

    @Test func conversionKeepsAlpha() {
        #expect(CSipColor(.srgb, 0.2, 0.4, 0.6, alpha: 0.25).converted(to: .oklch).alpha == 0.25)
    }
}

@Suite("Reference conversions")
struct ReferenceConversionTests {
    // Reference values: CSS Color 4 sample code / colorjs.io.

    @Test func srgbRedToOKLab() {
        expectComponents(CSipColor(.srgb, 1, 0, 0).converted(to: .oklab), .oklab,
                         [0.627955, 0.224863, 0.125846])
    }

    @Test func srgbPrimariesToOKLCH() {
        expectComponents(CSipColor(.srgb, 1, 0, 0).converted(to: .oklch), .oklch,
                         [0.627955, 0.257683, 29.2339])
        expectComponents(CSipColor(.srgb, 0, 1, 0).converted(to: .oklch), .oklch,
                         [0.866440, 0.294827, 142.4953])
        expectComponents(CSipColor(.srgb, 0, 0, 1).converted(to: .oklch), .oklch,
                         [0.452014, 0.313214, 264.0520])
    }

    @Test func whiteIsAchromaticInOKLCH() {
        let white = CSipColor(.srgb, 1, 1, 1).converted(to: .oklch)
        expectComponents(white, .oklch, [1, 0, 0], tolerance: 1e-6)
        #expect(white.components[2] == 0, "achromatic hue is stored as 0")
    }

    @Test func srgbToDisplayP3() {
        expectComponents(CSipColor(.srgb, 1, 0, 0).converted(to: .displayP3), .displayP3,
                         [0.917488, 0.200287, 0.138561])
    }

    @Test func displayP3RedToSRGBIsOutOfRange() {
        expectComponents(CSipColor(.displayP3, 1, 0, 0).converted(to: .srgb), .srgb,
                         [1.093091, -0.226753, -0.150140])
    }

    @Test func displayP3GreenToSRGBKeepsNegativeComponents() {
        let srgb = CSipColor(.displayP3, 0, 1, 0).converted(to: .srgb)
        expectComponents(srgb, .srgb, [-0.511567, 1.018276, -0.310711], tolerance: 1e-3)
        #expect(srgb.components[0] < 0 && srgb.components[2] < 0)
    }

    @Test func srgbToHSL() {
        // rgb(60 60 219)
        expectComponents(CSipColor(.srgb, 60 / 255, 60 / 255, 219 / 255).converted(to: .hsl), .hsl,
                         [240, 68.8312, 54.7059])
        expectComponents(CSipColor(.srgb, 0, 0.5, 0).converted(to: .hsl), .hsl, [120, 100, 25])
    }

    @Test func hslToSRGB() {
        expectComponents(CSipColor(.hsl, 120, 100, 25).converted(to: .srgb), .srgb, [0, 0.5, 0])
        expectComponents(CSipColor(.hsl, 0, 60, 50).converted(to: .srgb), .srgb, [0.8, 0.2, 0.2])
        expectComponents(CSipColor(.hsl, 300, 100, 50).converted(to: .srgb), .srgb, [1, 0, 1])
    }

    @Test func srgbToHWB() {
        expectComponents(CSipColor(.srgb, 60 / 255, 60 / 255, 219 / 255).converted(to: .hwb), .hwb,
                         [240, 23.5294, 14.1176])
    }

    @Test func hwbToSRGB() {
        expectComponents(CSipColor(.hwb, 0, 20, 20).converted(to: .srgb), .srgb, [0.8, 0.2, 0.2])
        // w + b ≥ 100% is a gray.
        expectComponents(CSipColor(.hwb, 90, 60, 60).converted(to: .srgb), .srgb, [0.5, 0.5, 0.5])
    }

    @Test func grayHasZeroHueInHSL() {
        let gray = CSipColor(.srgb, 0.5, 0.5, 0.5).converted(to: .hsl)
        expectComponents(gray, .hsl, [0, 0, 50])
    }
}

@Suite("Round trips")
struct RoundTripTests {
    static let samples: [CSipColor] = [
        CSipColor(.srgb, 0.2, 0.4, 0.6),
        CSipColor(.srgb, 0.9, 0.1, 0.3),
        CSipColor(.srgb, 0.25, 0.8, 0.15),
        CSipColor(.srgb, 60 / 255, 60 / 255, 219 / 255),
        CSipColor(.srgb, 0.95, 0.85, 0.05),
    ]

    @Test(arguments: ColorSpace.allCases)
    func roundTripsThroughEverySpace(via other: ColorSpace) {
        for sample in Self.samples {
            for space in ColorSpace.allCases {
                let start = sample.converted(to: space)
                let back = start.converted(to: other).converted(to: space)
                #expect(
                    componentsMatch(back.components, start.components, tolerance: 1e-9,
                                    hueIndex: space.hueIndex),
                    "\(space) → \(other) → \(space): \(start.components) vs \(back.components)"
                )
            }
        }
    }

    @Test func outOfRangeComponentsRoundTrip() {
        let p3Green = CSipColor(.displayP3, 0, 1, 0)
        let back = p3Green.converted(to: .srgb).converted(to: .displayP3)
        expectComponents(back, .displayP3, [0, 1, 0], tolerance: 1e-9)
        let wide = CSipColor(.srgb, 1.2, -0.3, 0.5)
        expectComponents(wide.converted(to: .oklab).converted(to: .srgb), .srgb,
                         [1.2, -0.3, 0.5], tolerance: 1e-9)
    }
}

@Suite("Perceptual equality")
struct PerceptualEqualityTests {
    @Test func deltaEOKIsEuclideanInOKLab() {
        let a = CSipColor(.oklab, 0.5, 0.1, 0.1)
        let b = CSipColor(.oklab, 0.5, 0.1 + 0.003, 0.1 + 0.004)
        #expect(abs(a.deltaEOK(b) - 0.005) < 1e-12)
    }

    @Test func belowThresholdIsEqual() {
        let a = CSipColor(.oklab, 0.5, 0.1, 0.1)
        #expect(a.isPerceptuallyEqual(to: CSipColor(.oklab, 0.5019, 0.1, 0.1)))
        #expect(!a.isPerceptuallyEqual(to: CSipColor(.oklab, 0.5021, 0.1, 0.1)))
    }

    @Test func worksAcrossSpaces() {
        let srgb = CSipColor(.srgb, 0.2, 0.4, 0.6)
        #expect(srgb.isPerceptuallyEqual(to: srgb.converted(to: .displayP3)))
        #expect(srgb.isPerceptuallyEqual(to: srgb.converted(to: .hsl)))
        #expect(!srgb.isPerceptuallyEqual(to: CSipColor(.srgb, 0.2, 0.42, 0.6)))
    }

    @Test func differentAlphaIsNotEqual() {
        let a = CSipColor(.srgb, 0.2, 0.4, 0.6, alpha: 1)
        #expect(!a.isPerceptuallyEqual(to: CSipColor(.srgb, 0.2, 0.4, 0.6, alpha: 0.5)))
        #expect(a.isPerceptuallyEqual(to: CSipColor(.srgb, 0.2, 0.4, 0.6, alpha: 0.999)))
    }
}

@Suite("Gamut mapping and hex")
struct GamutMappingTests {
    @Test func gamutChecks() {
        #expect(CSipColor(.srgb, 0.5, 0.5, 0.5).isInGamut(.srgb))
        #expect(!CSipColor(.displayP3, 1, 0, 0).isInGamut(.srgb))
        #expect(CSipColor(.srgb, 1, 0, 0).isInGamut(.displayP3))
        #expect(!CSipColor(.oklch, 0.7, 0.35, 150).isInGamut(.hsl))
        #expect(CSipColor(.oklch, 0.7, 0.35, 150).isInGamut(.oklch), "OKLab/OKLCH are unbounded")
    }

    @Test func inGamutColorIsOnlyConverted() {
        let color = CSipColor(.displayP3, 0.5, 0.4, 0.3, alpha: 0.7)
        let mapped = color.gamutMapped(to: .srgb)
        #expect(mapped == color.converted(to: .srgb))
    }

    @Test(arguments: [
        CSipColor(.displayP3, 1, 0, 0),
        CSipColor(.displayP3, 0, 1, 0),
        CSipColor(.displayP3, 0, 0, 1),
        CSipColor(.oklch, 0.7, 0.35, 150),
        CSipColor(.oklch, 0.5, 0.3, 300),
        CSipColor(.srgb, 1.2, -0.3, 0.5),
    ])
    func outOfGamutColorMapsIntoSRGB(_ color: CSipColor) {
        let origin = color.converted(to: .oklch)
        let mapped = color.gamutMapped(to: .srgb)
        #expect(mapped.colorSpace == .srgb)
        #expect(mapped.components.allSatisfy { (0...1).contains($0) }, "\(mapped.components)")
        let result = mapped.converted(to: .oklch)
        #expect(abs(result.components[0] - origin.components[0]) < 0.03, "lightness kept")
        #expect(componentsMatch([result.components[2]], [origin.components[2]], tolerance: 5,
                                hueIndex: 0), "hue kept")
        #expect(result.components[1] < origin.components[1], "chroma reduced")
    }

    @Test func extremeLightnessMapsToWhiteAndBlack() {
        let white = CSipColor(.oklch, 1.1, 0.2, 40).gamutMapped(to: .srgb)
        expectComponents(white, .srgb, [1, 1, 1], tolerance: 1e-12)
        let black = CSipColor(.oklch, -0.1, 0.2, 40).gamutMapped(to: .srgb)
        expectComponents(black, .srgb, [0, 0, 0], tolerance: 1e-12)
    }

    @Test func mappingToHSLStaysInSRGBGamut() {
        let mapped = CSipColor(.displayP3, 0, 1, 0).gamutMapped(to: .hsl)
        #expect(mapped.colorSpace == .hsl)
        #expect(mapped.converted(to: .srgb).components.allSatisfy { $0 >= -1e-9 && $0 <= 1 + 1e-9 })
    }

    @Test func mappingKeepsAlpha() {
        #expect(CSipColor(.displayP3, 1, 0, 0, alpha: 0.5).gamutMapped(to: .srgb).alpha == 0.5)
    }

    @Test func hex() {
        #expect(CSipColor(.srgb, 60 / 255, 60 / 255, 219 / 255).hex == "#3c3cdb")
        #expect(CSipColor(.srgb, 1, 1, 1).hex == "#ffffff")
        #expect(CSipColor(.srgb, 0, 0, 0).hex == "#000000")
        #expect(CSipColor(.srgb, 60 / 255, 60 / 255, 219 / 255, alpha: 0.8).hex == "#3c3cdbcc")
        #expect(CSipColor(.hsl, 120, 100, 25).hex == "#008000")
    }

    @Test func hexOfOutOfGamutColorIsGamutMapped() {
        let p3Red = CSipColor(.displayP3, 1, 0, 0)
        let mapped = p3Red.gamutMapped(to: .srgb)
        let expected = "#" + mapped.components
            .map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
        #expect(p3Red.hex == expected)
    }
}

@Suite("HSB")
struct HSBTests {
    @Test func srgbToHSB() {
        let hsb = CSipColor(.srgb, 60 / 255, 60 / 255, 219 / 255, alpha: 0.5).hsb()
        #expect(abs(hsb.hue - 240) < 1e-9)
        #expect(abs(hsb.saturation - 159.0 / 219.0) < 1e-9)
        #expect(abs(hsb.brightness - 219.0 / 255.0) < 1e-9)
        #expect(hsb.alpha == 0.5)
    }

    @Test func hsbToSRGB() {
        expectComponents(CSipColor(hsb: HSB(hue: 0, saturation: 0.75, brightness: 0.8)), .srgb,
                         [0.8, 0.2, 0.2])
        expectComponents(CSipColor(hsb: HSB(hue: 120, saturation: 1, brightness: 0.5)), .srgb,
                         [0, 0.5, 0])
    }

    @Test func hsbInDisplayP3() {
        let color = CSipColor(hsb: HSB(hue: 200, saturation: 0.6, brightness: 0.7, alpha: 0.9),
                          in: .displayP3)
        #expect(color.colorSpace == .displayP3)
        #expect(color.alpha == 0.9)
        let hsb = color.converted(to: .oklch).hsb(in: .displayP3)
        #expect(abs(hsb.hue - 200) < 1e-9)
        #expect(abs(hsb.saturation - 0.6) < 1e-9)
        #expect(abs(hsb.brightness - 0.7) < 1e-9)
    }

    @Test func grayHasZeroHueAndSaturation() {
        let hsb = CSipColor(.srgb, 0.4, 0.4, 0.4).hsb()
        #expect(hsb.hue == 0 && hsb.saturation == 0)
        #expect(CSipColor(.srgb, 0, 0, 0).hsb().saturation == 0)
    }
}
