import Foundation
import Testing
@testable import ColorsipCore

let redColor = CSipColor(.srgb, 1, 0, 0)
let greenColor = CSipColor(.srgb, 0, 1, 0)
let blueColor = CSipColor(.srgb, 0, 0, 1)
/// Perceptually equal to `red` (ΔEOK well below 0.002).
let almostRedColor = CSipColor(.srgb, 1, 0.0001, 0)

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
let t1 = t0.addingTimeInterval(60)
let t2 = t0.addingTimeInterval(120)

/// Expects `body` to throw exactly `expected`.
func expectError(
    _ expected: LibraryError, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> Void
) {
    #expect(throws: expected, sourceLocation: sourceLocation, performing: body)
}

/// A library with one palette "P" holding red and green (ungrouped) and a group "G" holding blue.
func sampleLibrary() throws -> (Library, palette: Palette.ID, group: SwatchGroup.ID) {
    var library = Library()
    let palette = library.createPalette(name: "P", at: t0)
    let group = try library.addGroup(name: "G", to: palette, at: t0)
    try library.insertSwatch(color: greenColor, name: "Green", into: .ungrouped(palette), at: t0)
    try library.insertSwatch(color: redColor, name: "Red", into: .ungrouped(palette), at: t0)
    try library.insertSwatch(color: blueColor, name: "Blue", into: .group(group, in: palette), at: t0)
    return (library, palette, group)
}

@Suite("Library: palettes")
struct LibraryPaletteTests {
    @Test func createPaletteAppendsWithTimestamps() {
        var library = Library()
        let a = library.createPalette(name: "A", at: t0)
        let b = library.createPalette(name: "B", at: t1)
        #expect(library.palettes.map(\.id) == [a, b])
        let palette = library.palettes[1]
        #expect(palette.name == "B")
        #expect(palette.createdAt == t1 && palette.modifiedAt == t1)
        #expect(!palette.isLocked && palette.icon == nil && palette.description == nil)
        #expect(palette.ungrouped.isEmpty && palette.groups.isEmpty)
    }

    @Test func timestampsAreRoundedToMilliseconds() {
        var library = Library()
        let id = library.createPalette(name: "A", at: Date(timeIntervalSince1970: 1.23419))
        #expect(library.palette(id)?.createdAt == Date(timeIntervalSince1970: 1.234))
    }

    @Test func metadataEditsTouchModifiedAt() throws {
        var library = Library()
        let id = library.createPalette(name: "A", at: t0)
        try library.renamePalette(id, to: "B", at: t1)
        try library.setDescription("About", of: id, at: t1)
        try library.setIcon(.emoji("🎨"), of: id, at: t2)
        let palette = try #require(library.palette(id))
        #expect(palette.name == "B" && palette.description == "About" && palette.icon == .emoji("🎨"))
        #expect(palette.createdAt == t0 && palette.modifiedAt == t2)
        try library.setIcon(.symbol("paintpalette"), of: id, at: t2)
        #expect(library.palette(id)?.icon == .symbol("paintpalette"))
    }

    @Test func movePalettes() {
        var library = Library()
        let ids = ["A", "B", "C", "D"].map { library.createPalette(name: $0, at: t0) }
        library.movePalettes(fromOffsets: [0, 2], toOffset: 4)
        #expect(library.palettes.map(\.id) == [ids[1], ids[3], ids[0], ids[2]])
        library.movePalettes(fromOffsets: [3], toOffset: 0)
        #expect(library.palettes.map(\.id) == [ids[2], ids[1], ids[3], ids[0]])
    }

    @Test func duplicateCopiesContentWithNewIds() throws {
        var (library, palette, _) = try sampleLibrary()
        try library.setLocked(true, palette: palette, at: t0)
        let copy = try library.duplicatePalette(palette, at: t1)
        #expect(library.palettes.map(\.id) == [palette, copy])
        let original = try #require(library.palette(palette))
        let duplicate = try #require(library.palette(copy))
        #expect(duplicate.name == "P copy")
        #expect(!duplicate.isLocked)
        #expect(duplicate.createdAt == t1 && duplicate.modifiedAt == t1)
        #expect(duplicate.ungrouped.map(\.color) == original.ungrouped.map(\.color))
        #expect(duplicate.ungrouped.map(\.name) == original.ungrouped.map(\.name))
        #expect(duplicate.groups.map(\.name) == original.groups.map(\.name))
        let originalIDs = Set(original.allSwatches.map(\.id) + original.groups.map(\.id))
        let copyIDs = Set(duplicate.allSwatches.map(\.id) + duplicate.groups.map(\.id))
        #expect(originalIDs.isDisjoint(with: copyIDs))
    }

    @Test func deletePalette() throws {
        var (library, palette, _) = try sampleLibrary()
        try library.deletePalette(palette)
        #expect(library.palettes.isEmpty)
        expectError(.notFound) { try library.deletePalette(palette) }
    }

    @Test func unknownPaletteIsNotFound() {
        var library = Library()
        expectError(.notFound) { try library.renamePalette(UUID(), to: "X", at: t0) }
    }
}

@Suite("Library: pick target")
struct LibraryPickTargetTests {
    @Test func atMostOneTarget() throws {
        var library = Library()
        let a = library.createPalette(name: "A", at: t0)
        let b = library.createPalette(name: "B", at: t0)
        try library.setPickTarget(a)
        #expect(library.pickTarget == a)
        try library.setPickTarget(b)
        #expect(library.pickTarget == b)
        try library.setPickTarget(nil)
        #expect(library.pickTarget == nil)
    }

    @Test func unknownTargetIsRefused() {
        var library = Library()
        expectError(.notFound) { try library.setPickTarget(UUID()) }
    }

    @Test func lockedPaletteCantBeTarget() throws {
        var library = Library()
        let a = library.createPalette(name: "A", at: t0)
        try library.setLocked(true, palette: a, at: t0)
        expectError(.locked(a)) { try library.setPickTarget(a) }
        #expect(library.pickTarget == nil)
    }

    @Test func lockingTheTargetClearsIt() throws {
        var library = Library()
        let a = library.createPalette(name: "A", at: t0)
        try library.setPickTarget(a)
        try library.setLocked(true, palette: a, at: t1)
        #expect(library.pickTarget == nil)
        try library.setLocked(false, palette: a, at: t1)
        #expect(library.pickTarget == nil)
    }

    @Test func deletingTheTargetClearsIt() throws {
        var library = Library()
        let a = library.createPalette(name: "A", at: t0)
        try library.setPickTarget(a)
        try library.deletePalette(a)
        #expect(library.pickTarget == nil)
    }

    @Test func initDropsInvalidTarget() {
        var palette = Palette(name: "A", at: t0)
        palette.isLocked = true
        #expect(Library(palettes: [palette], pickTarget: palette.id).pickTarget == nil)
        #expect(Library(palettes: [], pickTarget: UUID()).pickTarget == nil)
    }
}

@Suite("Library: groups")
struct LibraryGroupTests {
    @Test func addRenameMoveGroups() throws {
        var library = Library()
        let p = library.createPalette(name: "P", at: t0)
        let a = try library.addGroup(name: "A", to: p, at: t1)
        let b = try library.addGroup(name: "B", to: p, at: t1)
        let c = try library.addGroup(name: "C", to: p, at: t1)
        #expect(library.palette(p)?.groups.map(\.id) == [a, b, c])
        #expect(library.palette(p)?.modifiedAt == t1)
        try library.renameGroup(b, in: p, to: "Bee", at: t2)
        #expect(library.palette(p)?.groups[1].name == "Bee")
        #expect(library.palette(p)?.modifiedAt == t2)
        try library.moveGroup(c, in: p, to: 0, at: t2)
        #expect(library.palette(p)?.groups.map(\.id) == [c, a, b])
        try library.moveGroup(c, in: p, to: 2, at: t2)
        #expect(library.palette(p)?.groups.map(\.id) == [a, b, c])
    }

    @Test func deleteGroupWithSwatches() throws {
        var (library, p, g) = try sampleLibrary()
        try library.deleteGroup(g, in: p, keepSwatches: false, at: t1)
        let palette = try #require(library.palette(p))
        #expect(palette.groups.isEmpty)
        #expect(palette.ungrouped.map(\.name) == ["Red", "Green"])
    }

    @Test func deleteGroupKeepingSwatchesAppendsAndDropsDuplicates() throws {
        var (library, p, g) = try sampleLibrary()
        try library.insertSwatch(color: almostRedColor, name: "Red again", into: .group(g, in: p), at: t0)
        try library.deleteGroup(g, in: p, keepSwatches: true, at: t1)
        let palette = try #require(library.palette(p))
        #expect(palette.groups.isEmpty)
        // "Red again" duplicates the ungrouped "Red", so it's dropped.
        #expect(palette.ungrouped.map(\.name) == ["Red", "Green", "Blue"])
    }

    @Test func unknownGroupIsNotFound() throws {
        var (library, p, _) = try sampleLibrary()
        expectError(.notFound) { try library.renameGroup(UUID(), in: p, to: "X", at: t0) }
        expectError(.notFound) {
            try library.insertSwatch(color: redColor, name: "R", into: .group(UUID(), in: p), at: t0)
        }
    }
}

@Suite("Library: swatches")
struct LibrarySwatchTests {
    @Test func insertDefaultsToFront() throws {
        let (library, p, g) = try sampleLibrary()
        let palette = try #require(library.palette(p))
        #expect(palette.ungrouped.map(\.name) == ["Red", "Green"])
        #expect(palette.groups.first { $0.id == g }?.swatches.map(\.name) == ["Blue"])
        #expect(palette.ungrouped[0].createdAt == t0 && palette.ungrouped[0].modifiedAt == t0)
    }

    @Test func insertAtIndexAndTouchesPalette() throws {
        var (library, p, _) = try sampleLibrary()
        try library.insertSwatch(color: blueColor, name: "Blue", description: "Sky", into: .ungrouped(p), index: 2, at: t1)
        let palette = try #require(library.palette(p))
        #expect(palette.ungrouped.map(\.name) == ["Red", "Green", "Blue"])
        #expect(palette.ungrouped[2].description == "Sky")
        #expect(palette.modifiedAt == t1)
    }

    @Test func duplicateInSameSectionIsRefused() throws {
        var (library, p, g) = try sampleLibrary()
        let existing = try #require(library.palette(p)?.ungrouped.first { $0.name == "Red" })
        expectError(.duplicate(existing: existing.id)) {
            try library.insertSwatch(color: almostRedColor, name: "Again", into: .ungrouped(p), at: t1)
        }
        // The same color is fine in another section.
        try library.insertSwatch(color: redColor, name: "Red", into: .group(g, in: p), at: t1)
    }

    @Test func editSwatch() throws {
        var (library, p, _) = try sampleLibrary()
        let swatch = try #require(library.palette(p)?.ungrouped[0])
        try library.renameSwatch(swatch.id, in: .ungrouped(p), to: "Crimson", at: t1)
        try library.setSwatchDescription("Warm", of: swatch.id, in: .ungrouped(p), at: t1)
        try library.setSwatchColor(blueColor, of: swatch.id, in: .ungrouped(p), at: t2)
        let edited = try #require(library.palette(p)?.ungrouped[0])
        #expect(edited.name == "Crimson" && edited.description == "Warm" && edited.color == blueColor)
        #expect(edited.createdAt == t0 && edited.modifiedAt == t2)
        #expect(library.palette(p)?.modifiedAt == t2)
    }

    @Test func editingColorToADuplicateIsRefused() throws {
        var (library, p, _) = try sampleLibrary()
        let palette = try #require(library.palette(p))
        let (redSwatch, greenSwatch) = (palette.ungrouped[0], palette.ungrouped[1])
        expectError(.duplicate(existing: redSwatch.id)) {
            try library.setSwatchColor(almostRedColor, of: greenSwatch.id, in: .ungrouped(p), at: t1)
        }
        // Re-setting a swatch to (almost) its own color isn't a duplicate.
        try library.setSwatchColor(almostRedColor, of: redSwatch.id, in: .ungrouped(p), at: t1)
    }

    @Test func deleteSwatch() throws {
        var (library, p, _) = try sampleLibrary()
        let swatch = try #require(library.palette(p)?.ungrouped[0])
        try library.deleteSwatch(swatch.id, in: .ungrouped(p), at: t1)
        #expect(library.palette(p)?.ungrouped.map(\.name) == ["Green"])
        expectError(.notFound) { try library.deleteSwatch(swatch.id, in: .ungrouped(p), at: t1) }
    }

    @Test func reorderWithinSection() throws {
        var (library, p, _) = try sampleLibrary()
        try library.insertSwatch(color: blueColor, name: "Blue", into: .ungrouped(p), index: 2, at: t0)
        let redSwatch = try #require(library.palette(p)?.ungrouped[0])
        try library.moveSwatch(redSwatch.id, from: .ungrouped(p), to: .ungrouped(p), index: 2, at: t1)
        #expect(library.palette(p)?.ungrouped.map(\.name) == ["Green", "Blue", "Red"])
        try library.moveSwatch(redSwatch.id, from: .ungrouped(p), to: .ungrouped(p), index: 0, at: t1)
        #expect(library.palette(p)?.ungrouped.map(\.name) == ["Red", "Green", "Blue"])
    }

    @Test func moveBetweenPalettesKeepsId() throws {
        var (library, p, _) = try sampleLibrary()
        let q = library.createPalette(name: "Q", at: t0)
        let redSwatch = try #require(library.palette(p)?.ungrouped[0])
        try library.moveSwatch(redSwatch.id, from: .ungrouped(p), to: .ungrouped(q), index: 0, at: t1)
        #expect(library.palette(p)?.ungrouped.map(\.name) == ["Green"])
        #expect(library.palette(q)?.ungrouped.map(\.id) == [redSwatch.id])
        #expect(library.palette(p)?.modifiedAt == t1 && library.palette(q)?.modifiedAt == t1)
    }

    @Test func moveIntoDuplicateIsRefused() throws {
        var (library, p, g) = try sampleLibrary()
        try library.insertSwatch(color: blueColor, name: "Blue", into: .ungrouped(p), at: t0)
        let groupBlue = try #require(library.palette(p)?.groups[0].swatches[0])
        let ungroupedBlue = try #require(library.palette(p)?.ungrouped[0])
        let before = library
        expectError(.duplicate(existing: ungroupedBlue.id)) {
            try library.moveSwatch(groupBlue.id, from: .group(g, in: p), to: .ungrouped(p), index: 0, at: t1)
        }
        #expect(library == before)
    }

    @Test func copyMakesNewSwatch() throws {
        var (library, p, g) = try sampleLibrary()
        let redSwatch = try #require(library.palette(p)?.ungrouped[0])
        let copy = try library.copySwatch(redSwatch.id, from: .ungrouped(p), to: .group(g, in: p), index: 1, at: t1)
        let groupSwatches = try #require(library.palette(p)?.groups[0].swatches)
        #expect(groupSwatches.map(\.name) == ["Blue", "Red"])
        #expect(groupSwatches[1].id == copy && copy != redSwatch.id)
        #expect(groupSwatches[1].createdAt == t1)
        #expect(library.palette(p)?.ungrouped.count == 2)
        expectError(.duplicate(existing: copy)) {
            _ = try library.copySwatch(redSwatch.id, from: .ungrouped(p), to: .group(g, in: p), index: 0, at: t1)
        }
    }

    @Test func indicesAreClamped() throws {
        var (library, p, _) = try sampleLibrary()
        try library.insertSwatch(color: blueColor, name: "Blue", into: .ungrouped(p), index: 99, at: t0)
        #expect(library.palette(p)?.ungrouped.last?.name == "Blue")
    }
}

@Suite("Library: locked palettes")
struct LibraryLockTests {
    @Test func everyChangeIsRefused() throws {
        var (library, p, g) = try sampleLibrary()
        let other = library.createPalette(name: "Other", at: t0)
        try library.insertSwatch(color: blueColor, name: "Blue", into: .ungrouped(other), at: t0)
        let otherSwatch = try #require(library.palette(other)?.ungrouped[0])
        let redSwatch = try #require(library.palette(p)?.ungrouped[0])
        try library.setLocked(true, palette: p, at: t1)
        let before = library
        let refused: [(inout Library) throws(LibraryError) -> Void] = [
            { l throws(LibraryError) in try l.renamePalette(p, to: "X", at: t2) },
            { l throws(LibraryError) in try l.setDescription("X", of: p, at: t2) },
            { l throws(LibraryError) in try l.setIcon(.emoji("🔒"), of: p, at: t2) },
            { l throws(LibraryError) in try l.deletePalette(p) },
            { l throws(LibraryError) in _ = try l.addGroup(name: "X", to: p, at: t2) },
            { l throws(LibraryError) in try l.renameGroup(g, in: p, to: "X", at: t2) },
            { l throws(LibraryError) in try l.moveGroup(g, in: p, to: 0, at: t2) },
            { l throws(LibraryError) in try l.deleteGroup(g, in: p, keepSwatches: true, at: t2) },
            { l throws(LibraryError) in try l.insertSwatch(color: blueColor, name: "X", into: .ungrouped(p), at: t2) },
            { l throws(LibraryError) in try l.renameSwatch(redSwatch.id, in: .ungrouped(p), to: "X", at: t2) },
            { l throws(LibraryError) in try l.setSwatchDescription("X", of: redSwatch.id, in: .ungrouped(p), at: t2) },
            { l throws(LibraryError) in try l.setSwatchColor(blueColor, of: redSwatch.id, in: .ungrouped(p), at: t2) },
            { l throws(LibraryError) in try l.deleteSwatch(redSwatch.id, in: .ungrouped(p), at: t2) },
            { l throws(LibraryError) in
                try l.moveSwatch(redSwatch.id, from: .ungrouped(p), to: .ungrouped(p), index: 1, at: t2)
            },
            { l throws(LibraryError) in
                try l.moveSwatch(redSwatch.id, from: .ungrouped(p), to: .ungrouped(other), index: 0, at: t2)
            },
            { l throws(LibraryError) in
                _ = try l.copySwatch(otherSwatch.id, from: .ungrouped(other), to: .ungrouped(p), index: 0, at: t2)
            },
        ]
        for change in refused {
            expectError(.locked(p)) { try change(&library) }
            #expect(library == before)
        }
    }

    @Test func allowedChanges() throws {
        var (library, p, _) = try sampleLibrary()
        let other = library.createPalette(name: "Other", at: t0)
        let redSwatch = try #require(library.palette(p)?.ungrouped[0])
        try library.setLocked(true, palette: p, at: t1)
        #expect(library.palette(p)?.modifiedAt == t1)
        _ = try library.copySwatch(redSwatch.id, from: .ungrouped(p), to: .ungrouped(other), index: 0, at: t2)
        _ = try library.duplicatePalette(p, at: t2)
        library.movePalettes(fromOffsets: [0], toOffset: 3)
        #expect(library.palette(p)?.modifiedAt == t1)
        try library.setLocked(false, palette: p, at: t2)
        try library.renamePalette(p, to: "Unlocked", at: t2)
    }
}
