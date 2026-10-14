import Foundation
import Testing
@testable import ColorsipCore

/// A tiny seeded generator (SplitMix64), so random tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The nearest entry by brute force: smallest ΔEOK, first in list order on ties.
private struct BruteForce {
    let entries: [ColorName]
    let oklab: [CSipColor]

    init(_ names: ColorNames) {
        entries = names.entries
        oklab = entries.map { $0.color.converted(to: .oklab) }
    }

    func nearest(to color: CSipColor) -> ColorName? {
        let query = color.converted(to: .oklab)
        var best: (index: Int, distance: Double)?
        for (i, entry) in oklab.enumerated() {
            let d = entry.deltaEOK(query)
            if best == nil || d < best!.distance { best = (i, d) }
        }
        return best.map { entries[$0.index] }
    }
}

private func srgb(_ hex: Int) -> CSipColor {
    CSipColor(
        .srgb, Double((hex >> 16) & 0xff) / 255, Double((hex >> 8) & 0xff) / 255,
        Double(hex & 0xff) / 255)
}

@Suite("Color names: bundled list")
struct BundledColorNamesTests {
    @Test func loadsTheFullList() {
        #expect(ColorNames.shared.count == 31_935)
    }

    @Test(arguments: [
        (0xc93f38, "100 Mph"),
        (0xa59344, "18th Century Green"),
        (0x000000, "Black"),
        (0xffffff, "White"),
    ])
    func exactHitsReturnTheirName(hex: Int, name: String) {
        let match = ColorNames.shared.nearest(to: srgb(hex))
        #expect(match?.name == name)
        #expect(match?.color.hex == srgb(hex).hex)
    }

    @Test func friendlyNameIsTheNearestName() {
        #expect(srgb(0xc93f38).friendlyName == "100 Mph")
    }

    @Test func agreesWithBruteForce() {
        let reference = BruteForce(ColorNames.shared)
        var rng = SeededGenerator(state: 42)
        for _ in 0..<300 {
            // Includes values outside 0–1, so out-of-gamut colors are covered too.
            let color = CSipColor(
                .displayP3, .random(in: -0.1...1.1, using: &rng),
                .random(in: -0.1...1.1, using: &rng), .random(in: -0.1...1.1, using: &rng))
            let expected = reference.nearest(to: color)
            let actual = ColorNames.shared.nearest(to: color)
            #expect(actual == expected, "\(color.components)")
        }
    }

    @Test func worksInAnyColorSpaceAndIgnoresAlpha() {
        let reference = srgb(0xc93f38)
        let name = "100 Mph"
        for space in [ColorSpace.displayP3, .oklch, .oklab, .hsl, .hwb, .genericRGB] {
            #expect(reference.converted(to: space).friendlyName == name, "\(space)")
        }
        var translucent = reference
        translucent.alpha = 0.2
        #expect(translucent.friendlyName == name)
    }

    @Test func lookupIsFastEnoughForTheLoupe() {
        let names = ColorNames.shared
        var rng = SeededGenerator(state: 7)
        let queries = (0..<10_000).map { _ in
            CSipColor(
                .srgb, .random(in: 0...1, using: &rng), .random(in: 0...1, using: &rng),
                .random(in: 0...1, using: &rng))
        }
        let elapsed = ContinuousClock().measure {
            for query in queries { _ = names.nearest(to: query) }
        }
        #expect(elapsed < .seconds(1), "10,000 lookups took \(elapsed)")
    }
}

@Suite("Color names: parsing and edge cases")
struct ColorNamesParsingTests {
    @Test func emptyListHasNoNearest() {
        let names = ColorNames(csv: "")
        #expect(names.count == 0)
        #expect(names.nearest(to: srgb(0x123456)) == nil)
    }

    @Test func skipsHeaderAndMalformedLines() {
        let csv = """
            name,hex
            Good,#112233
            bad line
            No Hash,112233
            Short,#123
            ,#445566
            Not Hex,#zzzzzz
            Windows,#aabbcc\r
            Also Good,#ddeeff
            """
        let names = ColorNames(csv: csv)
        #expect(names.entries.map(\.name) == ["Good", "Windows", "Also Good"])
    }

    @Test func tiesGoToTheFirstEntry() {
        let names = ColorNames(csv: "First,#808080\nSecond,#808080\nThird,#808080")
        #expect(names.nearest(to: srgb(0x808080))?.name == "First")
        #expect(names.nearest(to: srgb(0x7f8081))?.name == "First")
    }

    @Test func picksTheNearestOfAFew() {
        let names = ColorNames(csv: "Red,#ff0000\nGreen,#00ff00\nBlue,#0000ff\nBlack,#000000")
        #expect(names.nearest(to: srgb(0xee1111))?.name == "Red")
        #expect(names.nearest(to: srgb(0x1010f0))?.name == "Blue")
        #expect(names.nearest(to: srgb(0x050505))?.name == "Black")
        #expect(names.nearest(to: CSipColor(.displayP3, 0, 1, 0))?.name == "Green")
    }

    @Test func smallTreesAgreeWithBruteForce() {
        var rng = SeededGenerator(state: 1)
        for size in [1, 2, 3, 7, 50] {
            let csv = (0..<size).map { i in
                "C\(i),#" + String(format: "%06x", Int.random(in: 0...0xffffff, using: &rng))
            }.joined(separator: "\n")
            let names = ColorNames(csv: csv)
            let reference = BruteForce(names)
            for _ in 0..<100 {
                let color = srgb(Int.random(in: 0...0xffffff, using: &rng))
                #expect(names.nearest(to: color) == reference.nearest(to: color))
            }
        }
    }
}
