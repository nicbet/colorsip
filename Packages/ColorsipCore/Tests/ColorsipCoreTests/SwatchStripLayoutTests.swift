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

    @Test func fewSwatchesSpreadToFillTheWidth() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 4), width: 320)
        #expect(layout.segmentWidth == 80)
        #expect(layout.contentWidth == 320)
        #expect(!layout.isScrollable)
        #expect(layout.sections.count == 1)
        #expect(layout.sections[0].x == 0)
        #expect(layout.sections[0].width == 320)
    }

    @Test func oneSwatchFillsTheStrip() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 1), width: 320)
        #expect(layout.segmentWidth == 320)
        #expect(layout.contentWidth == 320)
    }

    @Test func groupGapIsSixPoints() {
        #expect(SwatchStripLayout.groupGap == 6)
    }

    @Test func groupsAreSeparateSectionsWithAGap() {
        let p = palette(ungrouped: 2, groups: [3, 1])
        let layout = SwatchStripLayout(palette: p, width: 324)
        let gap = SwatchStripLayout.groupGap
        #expect(layout.sections.map(\.group) == [nil, p.groups[0].id, p.groups[1].id])
        // 6 swatches share the width left after two gaps: (324 - 12) / 6 = 52.
        #expect(layout.segmentWidth == 52)
        #expect(layout.sections.map(\.x) == [0, 104 + gap, 260 + 2 * gap])
        #expect(layout.sections.map(\.width) == [104, 156, 52])
        #expect(layout.sections.map(\.swatches.count) == [2, 3, 1])
        #expect(layout.contentWidth == 324)
    }

    @Test func swatchFramesFollowEachOther() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 2, groups: [2]), width: 326)
        let gap = SwatchStripLayout.groupGap
        #expect(layout.segmentWidth == 80)
        #expect(layout.sections[1].swatchX(1) == 160 + gap + 80)
    }

    @Test func emptySectionsAreLeftOut() {
        let p = palette(ungrouped: 0, groups: [0, 2, 0])
        let layout = SwatchStripLayout(palette: p, width: 320)
        #expect(layout.sections.map(\.group) == [p.groups[1].id])
        #expect(layout.sections[0].x == 0)
        #expect(layout.segmentWidth == 160)
        #expect(layout.contentWidth == 320)
    }

    @Test func paletteWithoutSwatchesIsEmpty() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 0, groups: [0, 0]), width: 320)
        #expect(layout.isEmpty)
        #expect(layout.sections.isEmpty)
        #expect(layout.contentWidth == 0)
        #expect(!layout.isScrollable)
    }

    @Test func swatchesWithoutAPaletteAreOneSection() {
        let layout = SwatchStripLayout(swatches: swatches(3), width: 320)
        #expect(layout.sections.count == 1)
        #expect(layout.sections[0].group == nil)
        #expect(layout.sections[0].swatches.count == 3)
        #expect(layout.contentWidth == 320)
        #expect(SwatchStripLayout(swatches: [], width: 320).isEmpty)
    }

    @Test func moreThanSixteenSwatchesScroll() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 20), width: 320)
        #expect(layout.contentWidth == 400)
        #expect(layout.isScrollable)
    }

    @Test func sixteenSwatchesInTwoGroupsFitWithoutScrolling() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 0, groups: [8, 8]), width: 326)
        #expect(layout.segmentWidth == 20)
        #expect(layout.contentWidth == 326)
        #expect(!layout.isScrollable)
    }

    @Test func overSixteenAcrossGroupsUseTheFixedWidth() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 9, groups: [8]), width: 320)
        #expect(layout.segmentWidth == 20)
        #expect(layout.contentWidth == 340 + SwatchStripLayout.groupGap)
        #expect(layout.isScrollable)
    }

    @Test func gapsWiderThanTheStripGiveZeroWidthSegments() {
        let layout = SwatchStripLayout(palette: palette(ungrouped: 1, groups: [1, 1]), width: 5)
        #expect(layout.segmentWidth == 0)
        #expect(layout.sections.allSatisfy { $0.width == 0 })
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
