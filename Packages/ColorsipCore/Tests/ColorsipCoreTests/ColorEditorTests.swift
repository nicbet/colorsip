import Foundation
import Testing
@testable import ColorsipCore

/// `#3c3cdb`, the spec's example color.
private let indigo = CSipColor(.srgb, 60.0 / 255, 60.0 / 255, 219.0 / 255)

private func editor(_ color: CSipColor, name: String? = nil, description: String? = nil) -> ColorEditor {
    ColorEditor(swatch: Swatch(color: color, name: name ?? color.friendlyName, description: description, createdAt: t0))
}

// `#expect` can't wrap a mutating call, so the result of `commit` goes through these.
private func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value, sourceLocation: sourceLocation)
}

private func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!value, sourceLocation: sourceLocation)
}

private func expectClose(
    _ a: [Double], _ b: [Double], tolerance: Double = 1e-6, sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(a.count == b.count, sourceLocation: sourceLocation)
    for (x, y) in zip(a, b) {
        #expect(abs(x - y) < tolerance, "\(a) vs \(b)", sourceLocation: sourceLocation)
    }
}

@Suite("Color editor: models and fields")
struct ColorEditorFieldTests {
    @Test func modelsInSwitcherOrder() {
        #expect(EditorModel.allCases == [.hex, .rgb, .hsb, .hsl, .oklch, .displayP3])
        #expect(EditorModel.allCases.map(\.displayName) == ["HEX", "RGB", "HSB", "HSL", "OKLCH", "P3"])
        #expect(EditorModel.hex.fieldLabels == ["HEX"])
        #expect(EditorModel.rgb.fieldLabels == ["R", "G", "B"])
        #expect(EditorModel.hsb.fieldLabels == ["H", "S", "B"])
        #expect(EditorModel.hsl.fieldLabels == ["H", "S", "L"])
        #expect(EditorModel.oklch.fieldLabels == ["L", "C", "H"])
        #expect(EditorModel.displayP3.fieldLabels == ["R", "G", "B"])
    }

    @Test func fieldsShowTheColorInEachModel() {
        let e = editor(indigo)
        #expect(e.fields(.hex) == ["#3c3cdb"])
        #expect(e.fields(.rgb) == ["60", "60", "219"])
        #expect(e.fields(.hsb) == ["240", "72.6", "85.9"])
        #expect(e.fields(.hsl) == ["240", "68.8", "54.7"])
        #expect(e.fields(.oklch) == ["47.5", "0.233", "273.1"])
        #expect(e.alphaField == "100")
        let p3 = editor(CSipColor(.displayP3, 0.2364, 0.2353, 0.8588))
        #expect(p3.fields(.displayP3) == ["0.236", "0.235", "0.859"])
    }

    @Test func alphaFieldIsAPercentage() {
        var color = indigo
        color.alpha = 0.5
        #expect(editor(color).alphaField == "50")
    }

    @Test func sRGBModelsShowTheMappedValueForAWideColor() {
        let e = editor(CSipColor(.displayP3, 1, 0, 0))
        #expect(e.isOutsideSRGB)
        #expect(e.fields(.hex) == [CSipColor(.displayP3, 1, 0, 0).hex])
        #expect(e.fields(.displayP3) == ["1", "0", "0"])
        #expect(!editor(indigo).isOutsideSRGB)
    }
}

@Suite("Color editor: working space")
struct ColorEditorWorkingSpaceTests {
    @Test func workingSpaceFollowsTheStoredSpace() {
        #expect(editor(indigo).workingSpace == .srgb)
        #expect(editor(indigo.converted(to: .hsl)).workingSpace == .srgb)
        #expect(editor(indigo.converted(to: .hwb)).workingSpace == .srgb)
        #expect(editor(indigo.converted(to: .genericRGB)).workingSpace == .genericRGB)
        #expect(editor(indigo.converted(to: .displayP3)).workingSpace == .displayP3)
        #expect(editor(indigo.converted(to: .oklch)).workingSpace == .displayP3)
        #expect(editor(indigo.converted(to: .oklab)).workingSpace == .displayP3)
    }

    @Test func anUnchangedColorKeepsItsSpaceAndComponentsExactly() {
        let oklch = CSipColor(.oklch, 0.5, 0.1, 200)
        var e = editor(oklch)
        e.setName("Teal-ish")
        #expect(e.color == oklch)
        #expect(!e.isColorChanged)
        #expect(e.hasChanges)
    }

    @Test func editsAreStoredInTheWorkingSpace() {
        var e = editor(CSipColor(.oklch, 0.5, 0.1, 200))
        e.setAlpha(0.5)
        #expect(e.color.colorSpace == .displayP3)
        #expect(e.color.alpha == 0.5)
        #expect(e.isColorChanged)
    }

    @Test func leavingSRGBPromotesToDisplayP3() {
        var e = editor(indigo)
        expectTrue(e.commit("1", field: 0, of: .displayP3))
        expectTrue(e.commit("0", field: 1, of: .displayP3))
        expectTrue(e.commit("0", field: 2, of: .displayP3))
        #expect(e.workingSpace == .displayP3)
        #expect(e.color.colorSpace == .displayP3)
        expectClose(e.color.components, [1, 0, 0])
        #expect(e.isOutsideSRGB)
    }

    @Test func aColorOutsideP3IsKeptUnclampedInP3() {
        var e = editor(CSipColor(.srgb, 0, 0.5, 0))
        expectTrue(e.commit("0.4", field: 1, of: .oklch))
        #expect(e.workingSpace == .displayP3)
        #expect(!e.color.isInGamut(.displayP3))
        expectClose([e.color.converted(to: .oklch).components[1]], [0.4], tolerance: 1e-9)
    }

    @Test func pickedColorsAreConvertedAndPromoted() {
        var e = editor(indigo)
        e.setPicked(CSipColor(.srgb, 1, 0, 0))
        #expect(e.workingSpace == .srgb)
        #expect(e.color == CSipColor(.srgb, 1, 0, 0))
        e.setPicked(CSipColor(.displayP3, 0, 1, 0))
        #expect(e.workingSpace == .displayP3)
        expectClose(e.color.components, [0, 1, 0])
    }
}

@Suite("Color editor: sliders and field")
struct ColorEditorHSBTests {
    @Test func saturationBrightnessAndHueEditHSBInTheWorkingSpace() {
        var e = editor(CSipColor(.displayP3, 1, 0, 0))
        e.setHue(120)
        e.setSaturation(1, brightness: 0.5)
        #expect(e.color.colorSpace == .displayP3)
        expectClose(e.color.components, [0, 0.5, 0])
        #expect(e.hsb == HSB(hue: 120, saturation: 1, brightness: 0.5))
    }

    @Test func slidersClampAndHueWraps() {
        var e = editor(indigo)
        e.setHue(360)
        #expect(e.hsb.hue == 0)
        e.setHue(-30)
        #expect(e.hsb.hue == 330)
        e.setSaturation(1.5, brightness: -1)
        #expect(e.hsb.saturation == 1 && e.hsb.brightness == 0)
        e.setAlpha(2)
        #expect(e.color.alpha == 1)
    }

    @Test func grayKeepsHueAndSaturation() {
        var e = editor(indigo)
        e.setHue(200)
        e.setSaturation(0.8, brightness: 0)
        #expect(e.hsb.hue == 200 && e.hsb.saturation == 0.8)
        e.setSaturation(0, brightness: 0.5)
        #expect(e.hsb.hue == 200)
        #expect(e.fields(.hsb) == ["200", "0", "50"])
    }

    @Test func typingAGrayKeepsTheHue() {
        var e = editor(indigo)
        expectTrue(e.commit("#808080", field: 0, of: .hex))
        #expect(e.hsb.hue == 240)
        #expect(e.hsb.saturation == 0)
    }
}

@Suite("Color editor: typed values")
struct ColorEditorCommitTests {
    @Test(arguments: [
        ("abc", [0xaa, 0xbb, 0xcc], 1.0),
        ("#ABC", [0xaa, 0xbb, 0xcc], 1.0),
        ("#abcd", [0xaa, 0xbb, 0xcc], 0xdd / 255.0),
        ("3C3CDB", [0x3c, 0x3c, 0xdb], 1.0),
        (" #3c3cdbcc ", [0x3c, 0x3c, 0xdb], 0xcc / 255.0),
    ])
    func hexInput(text: String, bytes: [Int], alpha: Double) {
        var e = editor(CSipColor(.srgb, 0, 0, 0))
        expectTrue(e.commit(text, field: 0, of: .hex))
        #expect(e.color.colorSpace == .srgb)
        expectClose(e.color.components, bytes.map { Double($0) / 255 })
        expectClose([e.color.alpha], [alpha])
    }

    @Test(arguments: ["#12", "xyz", "", "#12345", "#gggggg"])
    func invalidHexIsRejected(text: String) {
        var e = editor(indigo)
        expectFalse(e.commit(text, field: 0, of: .hex))
        #expect(e.color == indigo)
    }

    @Test func sixDigitHexKeepsAlpha() {
        var color = indigo
        color.alpha = 0.5
        var e = editor(color)
        expectTrue(e.commit("#ff0000", field: 0, of: .hex))
        #expect(e.color.alpha == 0.5)
    }

    @Test func rgbFieldsAreBytes() {
        var e = editor(indigo)
        expectTrue(e.commit("255", field: 0, of: .rgb))
        expectClose(e.color.components, [1, 60.0 / 255, 219.0 / 255])
        expectTrue(e.commit("300", field: 1, of: .rgb))
        #expect(e.fields(.rgb) == ["255", "255", "219"])
    }

    @Test func hsbHslAndOKLCHFields() {
        var e = editor(indigo)
        expectTrue(e.commit("120", field: 0, of: .hsb))
        #expect(e.fields(.hsb)[0] == "120")
        expectTrue(e.commit("50", field: 2, of: .hsl))
        #expect(e.fields(.hsl)[2] == "50")
        expectTrue(e.commit("60%", field: 0, of: .oklch))
        #expect(e.fields(.oklch)[0] == "60")
        expectTrue(e.commit("400", field: 2, of: .oklch))
        #expect(e.fields(.oklch)[2] == "40")
    }

    @Test func hueFieldsWrapAndPercentagesClamp() {
        var e = editor(indigo)
        expectTrue(e.commit("-90°", field: 0, of: .hsl))
        #expect(e.fields(.hsl)[0] == "270")
        expectTrue(e.commit("150", field: 1, of: .hsb))
        #expect(e.fields(.hsb)[1] == "100")
    }

    @Test func alphaField() {
        var e = editor(indigo)
        expectTrue(e.commitAlpha("25 %"))
        #expect(e.color.alpha == 0.25)
        #expect(e.alphaField == "25")
        expectFalse(e.commitAlpha("x"))
        expectTrue(e.commitAlpha("-5"))
        #expect(e.color.alpha == 0)
    }

    @Test func committingTheShownTextChangesNothing() {
        var e = editor(CSipColor(.srgb, 0.1234, 0.5678, 0.9012))
        for model in EditorModel.allCases {
            for (i, text) in e.fields(model).enumerated() {
                expectFalse(e.commit(text, field: i, of: model))
            }
        }
        expectFalse(e.commitAlpha(e.alphaField))
        #expect(!e.isColorChanged)
    }

    @Test func invalidNumbersAndBadFieldIndexesAreRejected() {
        var e = editor(indigo)
        expectFalse(e.commit("abc", field: 0, of: .rgb))
        expectFalse(e.commit("1", field: 3, of: .rgb))
        expectFalse(e.commit("1", field: 1, of: .hex))
        #expect(e.color == indigo)
    }

    @Test func acceptsACommaAsDecimalSeparator() {
        var e = editor(indigo)
        expectTrue(e.commit("0,5", field: 0, of: .displayP3))
        #expect(e.fields(.displayP3)[0] == "0.5")
    }
}

@Suite("Color editor: name, description and reset")
struct ColorEditorTextTests {
    @Test func autoNameFollowsTheColorUntilTyped() {
        var e = editor(indigo)
        #expect(e.name == indigo.friendlyName)
        e.setPicked(CSipColor(.srgb, 1, 0, 0))
        #expect(e.name == CSipColor(.srgb, 1, 0, 0).friendlyName)
        e.setName("Brand red")
        e.setPicked(CSipColor(.srgb, 0, 1, 0))
        #expect(e.name == "Brand red")
    }

    @Test func aCustomNameNeverFollows() {
        var e = editor(indigo, name: "Primary")
        e.setPicked(CSipColor(.srgb, 1, 0, 0))
        #expect(e.name == "Primary")
    }

    @Test func descriptionStartsFromTheSwatch() {
        var e = editor(indigo, description: "Buttons")
        #expect(e.description == "Buttons")
        #expect(editor(indigo).description == "")
        e.description = "Links"
        #expect(e.hasChanges)
    }

    @Test func resetRestoresTheOpeningState() {
        var e = editor(indigo, description: "Buttons")
        e.setPicked(CSipColor(.displayP3, 1, 0, 0))
        e.setName("Red")
        e.description = ""
        e.reset()
        #expect(e.color == indigo)
        #expect(e.workingSpace == .srgb)
        #expect(e.name == indigo.friendlyName)
        #expect(e.description == "Buttons")
        #expect(!e.hasChanges)
        // The name follows the color again after a reset.
        e.setPicked(CSipColor(.srgb, 1, 0, 0))
        #expect(e.name == CSipColor(.srgb, 1, 0, 0).friendlyName)
    }

    @Test func noChangesAtFirst() {
        #expect(!editor(indigo).hasChanges)
    }
}
