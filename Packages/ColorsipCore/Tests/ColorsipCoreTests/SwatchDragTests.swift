import Foundation
import Testing
@testable import ColorsipCore

/// A controller over a temporary library: palette "P" holds red and green (ungrouped) and group
/// "G" holds blue (see `sampleLibrary()`); palette "Q" is empty.
@MainActor
private struct Fixture {
    let temp = TempLibrary()
    let controller: LibraryController
    let p: Palette.ID
    let g: SwatchGroup.ID
    let q: Palette.ID

    init() throws {
        var (library, p, g) = try sampleLibrary()
        q = library.createPalette(name: "Q", at: t0)
        try temp.store.save(library, previous: nil)
        controller = LibraryController(store: temp.store)
        self.p = p
        self.g = g
    }

    var library: Library { controller.library }
    var red: Swatch { library.palette(p)!.ungrouped[0] }
    var green: Swatch { library.palette(p)!.ungrouped[1] }
    var blue: Swatch { library.palette(p)!.groups[0].swatches[0] }

    func names(_ palette: Palette.ID, _ group: SwatchGroup.ID? = nil) -> [String] {
        library.palette(palette)?.swatches(in: group)?.map(\.name) ?? []
    }
}

private func historySwatch(_ color: CSipColor = CSipColor(.srgb, 0.2, 0.4, 0.6), name: String = "Teal") -> Swatch {
    Swatch(color: color, name: name, description: "From history", createdAt: t0)
}

@MainActor
@Suite("Swatch drag: operation")
struct SwatchDragOperationTests {
    @Test func plainDragFromAPaletteMoves() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let source = SwatchDragSource.palette(f.red.id, in: .ungrouped(f.p))
        #expect(SwatchDrag.operation(for: source, onto: f.q, in: f.library, option: false) == .move)
        #expect(SwatchDrag.operation(for: source, onto: f.p, in: f.library, option: false) == .move)
    }

    @Test func optionCopies() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let source = SwatchDragSource.palette(f.red.id, in: .ungrouped(f.p))
        #expect(SwatchDrag.operation(for: source, onto: f.q, in: f.library, option: true) == .copy)
    }

    @Test func historyAlwaysCopies() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        #expect(SwatchDrag.operation(for: .history(historySwatch()), onto: f.q, in: f.library, option: false) == .copy)
    }

    @Test func lockedSourceAlwaysCopies() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        f.controller.setLocked(true, palette: f.p)
        let source = SwatchDragSource.palette(f.red.id, in: .ungrouped(f.p))
        #expect(SwatchDrag.operation(for: source, onto: f.q, in: f.library, option: false) == .copy)
    }

    @Test func lockedOrMissingDestinationIsRefused() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        f.controller.setLocked(true, palette: f.q)
        let source = SwatchDragSource.palette(f.red.id, in: .ungrouped(f.p))
        #expect(SwatchDrag.operation(for: source, onto: f.q, in: f.library, option: false) == nil)
        #expect(SwatchDrag.operation(for: source, onto: UUID(), in: f.library, option: false) == nil)
        #expect(SwatchDrag.operation(for: .history(historySwatch()), onto: f.q, in: f.library, option: true) == nil)
    }

    @Test func missingSourceIsRefused() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let gone = SwatchDragSource.palette(UUID(), in: .ungrouped(f.p))
        #expect(SwatchDrag.operation(for: gone, onto: f.q, in: f.library, option: false) == nil)
        let wrongSection = SwatchDragSource.palette(f.red.id, in: .group(f.g, in: f.p))
        #expect(SwatchDrag.operation(for: wrongSection, onto: f.q, in: f.library, option: false) == nil)
    }

    @Test func payloadIsTheValueInTheFormat() {
        #expect(SwatchDrag.payload(for: redColor, format: .cssHex) == "#ff0000")
        #expect(SwatchDrag.payload(for: redColor, format: .cssRGB) == OutputFormat.cssRGB.string(for: redColor))
    }
}

@MainActor
@Suite("Swatch drag: dropping")
struct SwatchDropTests {
    @Test func moveToAnotherPaletteKeepsTheSwatch() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let red = f.red
        let result = f.controller.dropSwatch(.palette(red.id, in: .ungrouped(f.p)), onto: .ungrouped(f.q), at: 0, option: false, at: t1)
        #expect(result == .moved(red.id))
        #expect(f.names(f.p) == ["Green"])
        #expect(f.library.palette(f.q)?.ungrouped.first?.id == red.id)
        #expect(f.controller.undoActionName == "Move Swatch")
        #expect(f.temp.store.load().library.palette(f.q)?.ungrouped.map(\.id) == [red.id])
        f.controller.undo()
        #expect(f.names(f.p) == ["Red", "Green"])
        #expect(f.names(f.q).isEmpty)
        f.controller.redo()
        #expect(f.names(f.q) == ["Red"])
    }

    @Test func moveBetweenSectionsOfAPalette() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let green = f.green
        #expect(f.controller.dropSwatch(.palette(green.id, in: .ungrouped(f.p)), onto: .group(f.g, in: f.p), at: 1, option: false) == .moved(green.id))
        #expect(f.names(f.p) == ["Red"])
        #expect(f.names(f.p, f.g) == ["Blue", "Green"])
    }

    @Test func reorderWithinASectionShiftsLaterSlots() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        // Red, Green: dropping Red into slot 2 (after Green) puts it last.
        let red = f.red
        #expect(f.controller.dropSwatch(.palette(red.id, in: .ungrouped(f.p)), onto: .ungrouped(f.p), at: 2, option: false) == .moved(red.id))
        #expect(f.names(f.p) == ["Green", "Red"])
        // And back to slot 0.
        #expect(f.controller.dropSwatch(.palette(red.id, in: .ungrouped(f.p)), onto: .ungrouped(f.p), at: 0, option: false) == .moved(red.id))
        #expect(f.names(f.p) == ["Red", "Green"])
    }

    @Test func droppingIntoItsOwnPlaceChangesNothing() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let source = SwatchDragSource.palette(f.red.id, in: .ungrouped(f.p))
        #expect(f.controller.dropSwatch(source, onto: .ungrouped(f.p), at: 0, option: false) == .unchanged)
        #expect(f.controller.dropSwatch(source, onto: .ungrouped(f.p), at: 1, option: false) == .unchanged)
        #expect(!f.controller.canUndo)
    }

    @Test func isUnchangedOnlyForAPlainDropIntoItsOwnPlace() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let source = SwatchDragSource.palette(f.green.id, in: .ungrouped(f.p))
        #expect(SwatchDrag.isUnchanged(source, onto: .ungrouped(f.p), at: 1, in: f.library, option: false))
        #expect(SwatchDrag.isUnchanged(source, onto: .ungrouped(f.p), at: 2, in: f.library, option: false))
        #expect(!SwatchDrag.isUnchanged(source, onto: .ungrouped(f.p), at: 0, in: f.library, option: false))
        #expect(!SwatchDrag.isUnchanged(source, onto: .ungrouped(f.p), at: 1, in: f.library, option: true))
        #expect(!SwatchDrag.isUnchanged(source, onto: .group(f.g, in: f.p), at: 0, in: f.library, option: false))
        #expect(!SwatchDrag.isUnchanged(.history(historySwatch()), onto: .ungrouped(f.p), at: 0, in: f.library, option: false))
    }

    @Test func optionCopiesWithANewID() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let red = f.red
        guard case .copied(let copy) = f.controller.dropSwatch(.palette(red.id, in: .ungrouped(f.p)), onto: .group(f.g, in: f.p), at: 0, option: true, at: t1) else {
            Issue.record("expected a copy"); return
        }
        #expect(copy != red.id)
        #expect(f.names(f.p) == ["Red", "Green"])
        #expect(f.names(f.p, f.g) == ["Red", "Blue"])
        let swatch = try #require(f.library.palette(f.p)?.groups[0].swatches[0])
        #expect(swatch.createdAt == t1)
        #expect(f.controller.undoActionName == "Copy Swatch")
    }

    @Test func historyCopiesNameAndDescription() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let teal = historySwatch()
        guard case .copied(let id) = f.controller.dropSwatch(.history(teal), onto: .ungrouped(f.q), at: 0, option: false, at: t1) else {
            Issue.record("expected a copy"); return
        }
        let swatch = try #require(f.library.palette(f.q)?.ungrouped.first)
        #expect(swatch.id == id && id != teal.id)
        #expect(swatch.name == "Teal" && swatch.description == "From history" && swatch.color == teal.color)
        #expect(swatch.createdAt == t1)
        #expect(f.controller.undoActionName == "Copy Swatch")
    }

    @Test func lockedSourceCopiesInsteadOfMoving() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        f.controller.setLocked(true, palette: f.p)
        let red = f.red
        guard case .copied = f.controller.dropSwatch(.palette(red.id, in: .ungrouped(f.p)), onto: .ungrouped(f.q), at: 0, option: false) else {
            Issue.record("expected a copy"); return
        }
        #expect(f.names(f.p) == ["Red", "Green"])
        #expect(f.names(f.q) == ["Red"])
    }

    @Test func duplicateIsRefusedWithTheExistingSwatch() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let blue = f.blue
        f.controller.dropSwatch(.palette(blue.id, in: .group(f.g, in: f.p)), onto: .ungrouped(f.q), at: 0, option: true)
        let qBlue = try #require(f.library.palette(f.q)?.ungrouped.first)
        let before = f.library
        let undoName = f.controller.undoActionName

        // Moving and copying into a section that already has the color.
        #expect(f.controller.dropSwatch(.palette(blue.id, in: .group(f.g, in: f.p)), onto: .ungrouped(f.q), at: 0, option: false) == .duplicate(existing: qBlue.id))
        #expect(f.controller.dropSwatch(.history(historySwatch(blueColor)), onto: .ungrouped(f.q), at: 0, option: false) == .duplicate(existing: qBlue.id))
        // Option-dragging within its own section duplicates itself.
        let red = f.red
        #expect(f.controller.dropSwatch(.palette(red.id, in: .ungrouped(f.p)), onto: .ungrouped(f.p), at: 2, option: true) == .duplicate(existing: red.id))
        #expect(f.library == before)
        #expect(f.controller.undoActionName == undoName)
    }

    @Test func lockedDestinationAndMissingIDsAreRefused() throws {
        let f = try Fixture()
        defer { f.temp.cleanUp() }
        let red = f.red
        f.controller.setLocked(true, palette: f.q)
        let before = f.library
        #expect(f.controller.dropSwatch(.palette(red.id, in: .ungrouped(f.p)), onto: .ungrouped(f.q), at: 0, option: false) == .refused)
        #expect(f.controller.dropSwatch(.history(historySwatch()), onto: .ungrouped(f.q), at: 0, option: false) == .refused)
        #expect(f.controller.dropSwatch(.palette(UUID(), in: .ungrouped(f.p)), onto: .ungrouped(f.p), at: 0, option: false) == .refused)
        #expect(f.controller.dropSwatch(.palette(red.id, in: .ungrouped(f.p)), onto: .group(UUID(), in: f.p), at: 0, option: false) == .refused)
        #expect(f.library == before)
        #expect(f.controller.undoActionName == "Lock Palette")
    }
}

private func stripPalette(ungrouped: Int, groups: [Int]) -> Palette {
    func swatches(_ count: Int, _ offset: Int) -> [Swatch] {
        (0..<count).map { Swatch(color: CSipColor(.srgb, Double($0 + offset) / 64, 0.5, 0.5), name: "\($0)", createdAt: t0) }
    }
    return Palette(
        name: "P", createdAt: t0, ungrouped: swatches(ungrouped, 0),
        groups: groups.enumerated().map { SwatchGroup(name: "G\($0.offset)", swatches: swatches($0.element, 10 * ($0.offset + 1))) })
}

@Suite("Swatch strip layout: drop slots")
struct SwatchStripDropSlotTests {
    // Ungrouped: 2 swatches, group A: 2 swatches. Width 206 = 4 × 50 + one 6 pt gap.
    // Ungrouped spans 0…100, the gap 100…106, group A 106…206.
    let palette = stripPalette(ungrouped: 2, groups: [2])
    var layout: SwatchStripLayout { SwatchStripLayout(palette: palette, width: 206) }
    var groupA: SwatchGroup.ID { palette.groups[0].id }

    @Test func slotIsTheNearestBoundaryInTheSection() {
        #expect(layout.segmentWidth == 50)
        #expect(layout.dropSlot(at: 10) == StripSlot(group: nil, index: 0))
        #expect(layout.dropSlot(at: 30) == StripSlot(group: nil, index: 1))
        #expect(layout.dropSlot(at: 80) == StripSlot(group: nil, index: 2))
        #expect(layout.dropSlot(at: 140) == StripSlot(group: groupA, index: 1))
        #expect(layout.dropSlot(at: 200) == StripSlot(group: groupA, index: 2))
    }

    @Test func theGapIsSplitInTheMiddle() {
        #expect(layout.dropSlot(at: 102.9) == StripSlot(group: nil, index: 2))
        #expect(layout.dropSlot(at: 103.1) == StripSlot(group: groupA, index: 0))
    }

    @Test func beforeTheFirstAndAfterTheLast() {
        #expect(layout.dropSlot(at: -40) == StripSlot(group: nil, index: 0))
        #expect(layout.dropSlot(at: 900) == StripSlot(group: groupA, index: 2))
    }

    @Test func emptyLayoutGivesTheFrontOfTheUngroupedSection() {
        let empty = SwatchStripLayout(palette: stripPalette(ungrouped: 0, groups: [0]), width: 200)
        #expect(empty.dropSlot(at: 50) == StripSlot(group: nil, index: 0))
    }

    @Test func layoutWithoutUngroupedSwatchesStartsWithTheGroup() {
        let p = stripPalette(ungrouped: 0, groups: [2])
        let layout = SwatchStripLayout(palette: p, width: 100)
        #expect(layout.dropSlot(at: 0) == StripSlot(group: p.groups[0].id, index: 0))
    }

    @Test func insertionLineSitsOnBoundariesAndInGaps() {
        #expect(layout.insertionX(for: StripSlot(group: nil, index: 0)) == 0)
        #expect(layout.insertionX(for: StripSlot(group: nil, index: 1)) == 50)
        #expect(layout.insertionX(for: StripSlot(group: nil, index: 2)) == 103)
        #expect(layout.insertionX(for: StripSlot(group: groupA, index: 0)) == 103)
        #expect(layout.insertionX(for: StripSlot(group: groupA, index: 2)) == 206)
        #expect(layout.insertionX(for: StripSlot(group: UUID(), index: 0)) == nil)
    }
}
