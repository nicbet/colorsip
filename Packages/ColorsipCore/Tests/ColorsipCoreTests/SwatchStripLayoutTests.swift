import Foundation
import Testing
@testable import ColorsipCore

private let date = Date(timeIntervalSince1970: 1_700_000_000)

private func swatches(_ count: Int) -> [Swatch] {
    (0..<count).map { i in
        Swatch(color: CSipColor(.srgb, Double(i) / 64, 0.5, 0.5), name: "Color \(i)", createdAt: date)
    }
}

private func palette(ungrouped: Int, groups: [Int] = []) -> Palette {
    Palette(
        name: "Palette", createdAt: date, ungrouped: swatches(ungrouped),
        groups: groups.enumerated().map { SwatchGroup(name: "Group \($0.offset)", swatches: swatches($0.element)) })
}

@Suite("Swatch strip layout")
struct SwatchStripLayoutTests {
    @Test func sixteenSwatchesFillTheWidth() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 16), width: 320)
        #expect(layout.segmentWidth == 20)
        #expect(layout.contentWidth == 320)
        #expect(!layout.isScrollable)
        #expect(!layout.isEmpty)
        #expect(layout.fades(offset: 0) == .init(leading: false, trailing: false))
    }

    @Test func segmentWidthIsFixedForFewSwatches() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 3), width: 320)
        #expect(layout.segmentWidth == 20)
        #expect(layout.contentWidth == 60)
        #expect(layout.sections.count == 1)
        #expect(layout.sections[0].x == 0)
        #expect(layout.sections[0].width == 60)
    }

    @Test func groupsAreSeparateSectionsWithAGap() {
        let p = palette(ungrouped: 2, groups: [3, 1])
        let layout = SwatchStripLayout(palette: p, width: 320)
        let gap = SwatchStripLayout.groupGap
        #expect(layout.sections.map(\.group) == [nil, p.groups[0].id, p.groups[1].id])
        #expect(layout.sections.map(\.x) == [0, 40 + gap, 100 + 2 * gap])
        #expect(layout.sections.map(\.width) == [40, 60, 20])
        #expect(layout.sections.map(\.swatches.count) == [2, 3, 1])
        #expect(layout.contentWidth == 120 + 2 * gap)
    }

    @Test func swatchFramesFollowEachOther() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 1, groups: [2]), width: 320)
        let gap = SwatchStripLayout.groupGap
        #expect(layout.sections[1].swatchX(1) == 20 + gap + 20)
    }

    @Test func emptySectionsAreLeftOut() {
        let p = palette(ungrouped: 0, groups: [0, 2, 0])
        let layout = SwatchStripLayout(palette: p, width: 320)
        #expect(layout.sections.map(\.group) == [p.groups[1].id])
        #expect(layout.sections[0].x == 0)
        #expect(layout.contentWidth == 40)
    }

    @Test func paletteWithoutSwatchesIsEmpty() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 0, groups: [0, 0]), width: 320)
        #expect(layout.isEmpty)
        #expect(layout.sections.isEmpty)
        #expect(layout.contentWidth == 0)
        #expect(!layout.isScrollable)
    }

    @Test func moreThanSixteenSwatchesScroll() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 20), width: 320)
        #expect(layout.contentWidth == 400)
        #expect(layout.isScrollable)
    }

    @Test func sixteenSwatchesInTwoGroupsScrollByTheGap() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 0, groups: [8, 8]), width: 320)
        #expect(layout.contentWidth == 320 + SwatchStripLayout.groupGap)
        #expect(layout.isScrollable)
    }

    @Test func fadesShowWhereThereIsMoreContent() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 20), width: 320)
        #expect(layout.fades(offset: 0) == .init(leading: false, trailing: true))
        #expect(layout.fades(offset: 40) == .init(leading: true, trailing: true))
        #expect(layout.fades(offset: 80) == .init(leading: true, trailing: false))
    }

    @Test func fadesTolerateSubpointOffsets() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 20), width: 320)
        #expect(layout.fades(offset: 0.3) == .init(leading: false, trailing: true))
        #expect(layout.fades(offset: 79.7) == .init(leading: true, trailing: false))
        // Rubber-band overscroll past either end.
        #expect(layout.fades(offset: -10) == .init(leading: false, trailing: true))
        #expect(layout.fades(offset: 95) == .init(leading: true, trailing: false))
    }

    @Test func zeroOrNegativeWidthIsSafe() {
        for width in [0.0, -5] {
            let layout = SwatchStripLayout(palette: palette(ungrouped: 3, groups: [2]), width: width)
            #expect(layout.segmentWidth == 0)
            #expect(layout.contentWidth >= 0)
            #expect(layout.sections.allSatisfy { $0.width >= 0 && $0.x >= 0 })
        }
    }
}
