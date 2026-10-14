import Testing
@testable import ColorsipCore

@MainActor
private final class FakeClipboard: Clipboard {
    var strings: [String] = []
    func setString(_ string: String) { strings.append(string) }
}

@MainActor
@Suite("Copying")
struct CopyingTests {
    @Test func copiesTheValueInTheFormat() {
        let clipboard = FakeClipboard()
        let color = CSipColor(.srgb, 60 / 255.0, 60 / 255.0, 219 / 255.0)
        copyValue(of: color, as: .cssHex, to: clipboard)
        copyValue(of: color, as: .cssRGB, to: clipboard)
        #expect(clipboard.strings == ["#3c3cdb", "rgb(60 60 219)"])
    }

    @Test func displayP3ComponentsAreGamutMapped() {
        let inGamut = CSipColor(.displayP3, 0.2, 0.4, 0.6, alpha: 0.5).displayP3Components
        #expect(componentsMatch([inGamut.red, inGamut.green, inGamut.blue], [0.2, 0.4, 0.6], tolerance: 1e-9))
        #expect(inGamut.alpha == 0.5)

        let outOfGamut = CSipColor(.oklch, 0.7, 0.4, 150).displayP3Components
        for c in [outOfGamut.red, outOfGamut.green, outOfGamut.blue] {
            #expect(c >= -1e-6 && c <= 1 + 1e-6)
        }
    }
}
