import Testing
@testable import ColorsipCore

/// `#3c3cdb`, stored in sRGB.
private let blue = CSipColor(.srgb, 60 / 255, 60 / 255, 219 / 255)
private let translucentBlue = CSipColor(.srgb, 60 / 255, 60 / 255, 219 / 255, alpha: 0.8)
/// The `spec.md` §5.1 example, stored in Display P3.
private let p3Blue = CSipColor(.displayP3, 0.2364, 0.2353, 0.8588)
/// Display P3 red, outside the sRGB gamut.
private let p3Red = CSipColor(.displayP3, 1, 0, 0)
/// An OKLCH green outside the Display P3 gamut.
private let wideGreen = CSipColor(.oklch, 0.7, 0.4, 150)

/// The numbers in a format's output, for example `[60, 60, 219]` for `rgb(60 60 219)`.
private func numbers(_ string: String) -> [Double] {
    string.split(whereSeparator: { " (),:%".contains($0) }).compactMap { Double($0) }
}

@Suite("Output formats: CSS")
struct CSSOutputFormatTests {
    @Test func hex() {
        #expect(blue.formatted(as: .cssHex) == "#3c3cdb")
        #expect(translucentBlue.formatted(as: .cssHex) == "#3c3cdbcc")
    }

    @Test func hexWithoutHash() {
        #expect(blue.formatted(as: .cssHexNoHash) == "3c3cdb")
        #expect(translucentBlue.formatted(as: .cssHexNoHash) == "3c3cdbcc")
    }

    @Test func rgb() {
        #expect(blue.formatted(as: .cssRGB) == "rgb(60 60 219)")
        #expect(translucentBlue.formatted(as: .cssRGB) == "rgb(60 60 219 / 80%)")
    }

    @Test func hsl() {
        #expect(blue.formatted(as: .cssHSL) == "hsl(240 68.83% 54.71%)")
        #expect(translucentBlue.formatted(as: .cssHSL) == "hsl(240 68.83% 54.71% / 80%)")
        #expect(CSipColor(.srgb, 1, 0, 0).formatted(as: .cssHSL) == "hsl(0 100% 50%)")
    }

    @Test func oklch() {
        #expect(blue.formatted(as: .cssOKLCH) == "oklch(47.5% 0.233 273.1)")
        #expect(translucentBlue.formatted(as: .cssOKLCH) == "oklch(47.5% 0.233 273.1 / 80%)")
    }

    @Test func displayP3() {
        #expect(p3Blue.formatted(as: .cssDisplayP3) == "color(display-p3 0.236 0.235 0.859)")
        #expect(
            CSipColor(.displayP3, 0.2364, 0.2353, 0.8588, alpha: 0.5).formatted(as: .cssDisplayP3)
                == "color(display-p3 0.236 0.235 0.859 / 50%)")
        #expect(CSipColor(.srgb, 1, 1, 1).formatted(as: .cssDisplayP3) == "color(display-p3 1 1 1)")
    }

    @Test func cssAlphaKeepsOneDecimal() {
        let color = CSipColor(.srgb, 0, 0, 0, alpha: 0.333)
        #expect(color.formatted(as: .cssRGB) == "rgb(0 0 0 / 33.3%)")
    }
}

@Suite("Output formats: Apple")
struct AppleOutputFormatTests {
    @Test func swiftUI() {
        #expect(p3Blue.formatted(as: .swiftUI)
            == "Color(.displayP3, red: 0.236, green: 0.235, blue: 0.859, opacity: 1)")
        #expect(translucentBlue.formatted(as: .swiftUI)
            == "Color(.sRGB, red: 0.235, green: 0.235, blue: 0.859, opacity: 0.8)")
    }

    @Test func nsColor() {
        #expect(p3Blue.formatted(as: .nsColor)
            == "NSColor(displayP3Red: 0.236, green: 0.235, blue: 0.859, alpha: 1)")
        #expect(blue.formatted(as: .nsColor)
            == "NSColor(srgbRed: 0.235, green: 0.235, blue: 0.859, alpha: 1)")
    }

    @Test func uiColor() {
        #expect(p3Blue.formatted(as: .uiColor)
            == "UIColor(displayP3Red: 0.236, green: 0.235, blue: 0.859, alpha: 1)")
        #expect(blue.formatted(as: .uiColor)
            == "UIColor(red: 0.235, green: 0.235, blue: 0.859, alpha: 1)")
    }

    @Test func hslAndHWBColorsUseSRGB() {
        #expect(CSipColor(.hsl, 0, 100, 50).formatted(as: .swiftUI)
            == "Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)")
        #expect(CSipColor(.hwb, 0, 0, 0).formatted(as: .nsColor)
            == "NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)")
    }

    @Test func otherSpacesUseDisplayP3() {
        #expect(CSipColor(.genericRGB, 1, 1, 1).formatted(as: .uiColor)
            == "UIColor(displayP3Red: 1, green: 1, blue: 1, alpha: 1)")
        #expect(CSipColor(.oklab, 1, 0, 0).formatted(as: .swiftUI)
            == "Color(.displayP3, red: 1, green: 1, blue: 1, opacity: 1)")
    }

    @Test func outOfP3ColorsAreGamutMappedToP3() {
        for format in [OutputFormat.swiftUI, .nsColor, .uiColor] {
            let values = numbers(wideGreen.formatted(as: format))
            #expect(values.count == 4)
            #expect(values.allSatisfy { $0 >= 0 && $0 <= 1 }, "\(format): \(values)")
        }
    }

    @Test func outOfSRGBColorsStoredInSRGBAreGamutMapped() {
        let extended = CSipColor(.srgb, 1.2, -0.1, 0)
        let values = numbers(extended.formatted(as: .nsColor))
        #expect(values.allSatisfy { $0 >= 0 && $0 <= 1 }, "\(values)")
    }
}

@Suite("Output formats: Android")
struct AndroidOutputFormatTests {
    @Test func android() {
        #expect(blue.formatted(as: .android) == "0xFF3C3CDB")
        #expect(translucentBlue.formatted(as: .android) == "0xCC3C3CDB")
    }

    @Test func androidXML() {
        #expect(blue.formatted(as: .androidXML) == "#FF3C3CDB")
        #expect(translucentBlue.formatted(as: .androidXML) == "#CC3C3CDB")
    }
}

@Suite("Output formats: gamut mapping")
struct OutputFormatGamutTests {
    private var mappedRed: CSipColor { p3Red.gamutMapped(to: .srgb) }

    @Test func srgbFormatsAreGamutMapped() {
        let hex = p3Red.hex
        #expect(p3Red.formatted(as: .cssHex) == hex)
        #expect(p3Red.formatted(as: .cssHexNoHash) == String(hex.dropFirst()))
        #expect(p3Red.formatted(as: .android) == "0xFF" + hex.dropFirst().uppercased())
        #expect(p3Red.formatted(as: .androidXML) == "#FF" + hex.dropFirst().uppercased())

        let rgb = numbers(p3Red.formatted(as: .cssRGB))
        let expected = mappedRed.components.map { ($0 * 255).rounded() }
        #expect(rgb == expected)

        let hsl = numbers(p3Red.formatted(as: .cssHSL))
        #expect(hsl.count == 3)
        #expect(hsl[1] <= 100 && hsl[2] <= 100)
    }

    @Test func oklchIsNotMapped() {
        let chroma = numbers(p3Red.formatted(as: .cssOKLCH))[1]
        let original = p3Red.converted(to: .oklch).components[1]
        #expect(abs(chroma - original) < 0.0005)
        #expect(chroma > mappedRed.converted(to: .oklch).components[1] + 0.01)
    }

    @Test func displayP3IsNotMappedToSRGB() {
        #expect(p3Red.formatted(as: .cssDisplayP3) == "color(display-p3 1 0 0)")
    }

    @Test func displayP3IsMappedToP3() {
        let values = numbers(wideGreen.formatted(as: .cssDisplayP3))
        #expect(values.count == 3)
        #expect(values.allSatisfy { $0 >= 0 && $0 <= 1 }, "\(values)")
    }
}

@Suite("Output formats: rounding")
struct OutputFormatRoundingTests {
    @Test func hueThatRoundsTo360IsWrittenAsZero() {
        #expect(CSipColor(.hsl, 359.996, 100, 50).formatted(as: .cssHSL) == "hsl(0 100% 50%)")
        #expect(CSipColor(.oklch, 0.5, 0.1, 359.96).formatted(as: .cssOKLCH) == "oklch(50% 0.1 0)")
    }

    @Test func negativeHueIsNormalized() {
        #expect(CSipColor(.oklch, 0.5, 0.1, -0.01).formatted(as: .cssOKLCH) == "oklch(50% 0.1 0)")
    }

    @Test func nearlyOpaqueAlphaIsLeftOut() {
        let color = CSipColor(.srgb, 0, 0, 0, alpha: 0.9999)
        #expect(color.formatted(as: .cssRGB) == "rgb(0 0 0)")
        #expect(color.formatted(as: .cssHex) == "#000000")
    }

    @Test func numbersDropTrailingZerosAndNegativeZero() {
        #expect(OutputFormat.number(1, decimals: 3) == "1")
        #expect(OutputFormat.number(0.5, decimals: 3) == "0.5")
        #expect(OutputFormat.number(0.2364, decimals: 3) == "0.236")
        #expect(OutputFormat.number(-0.0001, decimals: 3) == "0")
        #expect(OutputFormat.number(-0.25, decimals: 3) == "-0.25")
        #expect(OutputFormat.number(219.4, decimals: 0) == "219")
    }
}
