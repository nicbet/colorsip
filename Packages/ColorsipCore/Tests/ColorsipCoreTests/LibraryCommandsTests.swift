import Foundation
import Testing
@testable import ColorsipCore

/// A controller over a fresh temporary library, with a palette "P" holding red and green
/// (ungrouped) and a group "G" holding blue (see `sampleLibrary()`).
@MainActor
private func sampleController() throws -> (LibraryController, TempLibrary, palette: Palette.ID, group: SwatchGroup.ID) {
    let temp = TempLibrary()
    let (library, palette, group) = try sampleLibrary()
    try temp.store.save(library, previous: nil)
    return (LibraryController(store: temp.store), temp, palette, group)
}

@MainActor
@Suite("Library commands: palettes")
struct LibraryPaletteCommandTests {
    @Test func newPaletteInsertsANumberedUntitledPaletteAtTheTopAndSaves() {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        let controller = LibraryController(store: temp.store)
        let a = controller.newPalette(at: t0)
        let b = controller.newPalette(at: t1)
        controller.renamePalette(a, to: "new palette")
        let c = controller.newPalette(at: t2)
        controller.renamePalette(a, to: "Brand")
        let d = controller.newPalette(at: t2)

        #expect(controller.library.palettes.map(\.id) == [d, c, b, a])
        #expect(controller.library.palettes.map(\.name) == ["New Palette", "New Palette 3", "New Palette 2", "Brand"])
        #expect(controller.library.palette(b)?.createdAt == t1)
        #expect(controller.library.pickTarget == nil)
        #expect(controller.undoActionName == "New Palette")
        #expect(temp.store.load().library.palettes.map(\.id) == [d, c, b, a])
    }

    @Test func renameTrimsAndIgnoresEmptyNames() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        #expect(controller.renamePalette(palette, to: "  Brand \n", at: t1))
        #expect(controller.library.palette(palette)?.name == "Brand")
        #expect(controller.undoActionName == "Rename Palette")

        #expect(!controller.renamePalette(palette, to: "   ", at: t2))
        #expect(!controller.renamePalette(palette, to: "Brand", at: t2))
        #expect(controller.library.palette(palette)?.name == "Brand")
        controller.undo()
        #expect(controller.library.palette(palette)?.name == "P")
    }

    @Test func descriptionIsTrimmedAndEmptyClearsIt() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        #expect(controller.setDescription("  Brand colors ", of: palette))
        #expect(controller.library.palette(palette)?.description == "Brand colors")
        #expect(controller.undoActionName == "Edit Description")
        #expect(controller.setDescription(" ", of: palette))
        #expect(controller.library.palette(palette)?.description == nil)
        #expect(!controller.setDescription(nil, of: palette))
    }

    @Test func setIcon() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        #expect(controller.setIcon(.symbol("star"), of: palette))
        #expect(controller.library.palette(palette)?.icon == .symbol("star"))
        #expect(controller.undoActionName == "Set Icon")
        #expect(controller.setIcon(nil, of: palette))
        #expect(controller.library.palette(palette)?.icon == nil)
    }

    @Test func lockAndUnlockAreNamedAndLockingClearsThePickTarget() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        controller.togglePickTarget(palette)
        #expect(controller.setLocked(true, palette: palette))
        #expect(controller.undoActionName == "Lock Palette")
        #expect(controller.library.pickTarget == nil)
        #expect(controller.setLocked(false, palette: palette))
        #expect(controller.undoActionName == "Unlock Palette")
    }

    @Test func lockedPalettesRefuseEditsWithoutAnUndoStep() throws {
        let (controller, temp, palette, group) = try sampleController()
        defer { temp.cleanUp() }
        controller.setLocked(true, palette: palette)
        let before = controller.library
        let swatch = try #require(before.palette(palette)?.ungrouped.first?.id)

        #expect(!controller.renamePalette(palette, to: "X"))
        #expect(!controller.setDescription("X", of: palette))
        #expect(!controller.setIcon(.emoji("🎨"), of: palette))
        #expect(!controller.deletePalette(palette))
        #expect(!controller.togglePickTarget(palette))
        #expect(controller.newGroup(in: palette) == nil)
        #expect(!controller.renameGroup(group, in: palette, to: "X"))
        #expect(!controller.moveGroup(group, in: palette, by: -1))
        #expect(!controller.deleteGroup(group, in: palette, keepSwatches: false))
        #expect(!controller.renameSwatch(swatch, in: .ungrouped(palette), to: "X"))
        #expect(!controller.deleteSwatch(swatch, in: .ungrouped(palette)))
        #expect(controller.library == before)
        #expect(controller.undoActionName == "Lock Palette")
    }

    @Test func missingIdsChangeNothing() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        let before = controller.library
        #expect(!controller.renamePalette(UUID(), to: "X"))
        #expect(controller.duplicatePalette(UUID()) == nil)
        #expect(!controller.deletePalette(UUID()))
        #expect(!controller.movePalette(UUID(), before: nil))
        #expect(!controller.renameGroup(UUID(), in: palette, to: "X"))
        #expect(!controller.deleteSwatch(UUID(), in: .ungrouped(palette)))
        #expect(controller.library == before)
        #expect(!controller.canUndo)
    }

    @Test func duplicateInsertsAfterTheOriginal() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        let copy = try #require(controller.duplicatePalette(palette, at: t1))
        #expect(controller.library.palettes.map(\.id) == [palette, copy])
        #expect(controller.undoActionName == "Duplicate Palette")
    }

    @Test func deleteClearsThePickTarget() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        controller.togglePickTarget(palette)
        #expect(controller.deletePalette(palette))
        #expect(controller.library.palettes.isEmpty)
        #expect(controller.library.pickTarget == nil)
        #expect(controller.undoActionName == "Delete Palette")
        controller.undo()
        #expect(controller.library.pickTarget == palette)
    }

    @Test func movePaletteBeforeAnotherOrToTheEnd() {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        let controller = LibraryController(store: temp.store)
        for _ in 0..<3 { controller.newPalette(at: t0) }
        let ids = controller.library.palettes.map(\.id)
        #expect(controller.movePalette(ids[2], before: ids[0]))
        #expect(controller.library.palettes.map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(controller.undoActionName == "Move Palette")
        #expect(controller.movePalette(ids[2], before: nil))
        #expect(controller.library.palettes.map(\.id) == [ids[0], ids[1], ids[2]])
        #expect(temp.store.load().library.palettes.map(\.id) == [ids[0], ids[1], ids[2]])
    }

    @Test func selectPickTargetOnlySelects() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        #expect(controller.selectPickTarget(palette))
        #expect(controller.library.pickTarget == palette)
        #expect(controller.undoActionName == "Set Pick Target")
        controller.setLocked(true, palette: controller.newPalette())
        #expect(!controller.selectPickTarget(palette))
        #expect(controller.library.pickTarget == palette)
        #expect(controller.undoActionName == "Lock Palette")

        let locked = try #require(controller.library.palettes.first { $0.isLocked }?.id)
        #expect(!controller.selectPickTarget(locked))
        #expect(!controller.selectPickTarget(UUID()))
        #expect(controller.library.pickTarget == palette)
    }

    @Test func togglePickTargetSetsAndClears() throws {
        let (controller, temp, palette, _) = try sampleController()
        defer { temp.cleanUp() }
        #expect(controller.togglePickTarget(palette))
        #expect(controller.library.pickTarget == palette)
        #expect(controller.undoActionName == "Set Pick Target")
        #expect(controller.togglePickTarget(palette))
        #expect(controller.library.pickTarget == nil)
    }
}

@MainActor
@Suite("Library commands: groups and swatches")
struct LibraryGroupCommandTests {
    @Test func newGroupAppendsANumberedGroup() throws {
        let (controller, temp, palette, group) = try sampleController()
        defer { temp.cleanUp() }
        let a = try #require(controller.newGroup(in: palette))
        let b = try #require(controller.newGroup(in: palette))
        let groups = try #require(controller.library.palette(palette)?.groups)
        #expect(groups.map(\.id) == [group, a, b])
        #expect(groups.map(\.name) == ["G", "New Group", "New Group 2"])
        #expect(controller.undoActionName == "New Group")
    }

    @Test func renameGroupTrimsAndIgnoresEmptyNames() throws {
        let (controller, temp, palette, group) = try sampleController()
        defer { temp.cleanUp() }
        #expect(controller.renameGroup(group, in: palette, to: " Blues "))
        #expect(controller.library.palette(palette)?.groups.first?.name == "Blues")
        #expect(controller.undoActionName == "Rename Group")
        #expect(!controller.renameGroup(group, in: palette, to: ""))
    }

    @Test func moveGroupByOneClampedAtTheEnds() throws {
        let (controller, temp, palette, g) = try sampleController()
        defer { temp.cleanUp() }
        let h = try #require(controller.newGroup(in: palette))
        #expect(!controller.moveGroup(g, in: palette, by: -1))
        #expect(controller.moveGroup(g, in: palette, by: 1))
        #expect(controller.library.palette(palette)?.groups.map(\.id) == [h, g])
        #expect(controller.undoActionName == "Move Group")
        #expect(!controller.moveGroup(g, in: palette, by: 1))
        #expect(controller.moveGroup(g, in: palette, by: -1))
        #expect(controller.library.palette(palette)?.groups.map(\.id) == [g, h])
    }

    @Test func deleteGroupKeepingOrDroppingSwatches() throws {
        let (controller, temp, palette, group) = try sampleController()
        defer { temp.cleanUp() }
        #expect(controller.deleteGroup(group, in: palette, keepSwatches: true))
        #expect(controller.library.palette(palette)?.ungrouped.map(\.name) == ["Red", "Green", "Blue"])
        #expect(controller.undoActionName == "Delete Group")
        controller.undo()
        #expect(controller.deleteGroup(group, in: palette, keepSwatches: false))
        #expect(controller.library.palette(palette)?.allSwatches.map(\.name) == ["Red", "Green"])
    }

    @Test func renameAndDeleteSwatch() throws {
        let (controller, temp, palette, group) = try sampleController()
        defer { temp.cleanUp() }
        let section = SectionID.group(group, in: palette)
        let blue = try #require(controller.library.palette(palette)?.groups.first?.swatches.first?.id)
        #expect(controller.renameSwatch(blue, in: section, to: " Navy "))
        #expect(controller.library.palette(palette)?.groups.first?.swatches.first?.name == "Navy")
        #expect(controller.undoActionName == "Rename Swatch")
        #expect(!controller.renameSwatch(blue, in: section, to: " "))
        #expect(controller.deleteSwatch(blue, in: section))
        #expect(controller.library.palette(palette)?.groups.first?.swatches.isEmpty == true)
        #expect(controller.undoActionName == "Delete Swatch")
    }
}

@Suite("Library: names and moves")
struct LibraryNameTests {
    @Test func uniqueName() {
        #expect(Library.uniqueName("New Palette", among: []) == "New Palette")
        #expect(Library.uniqueName("New Palette", among: ["NEW PALETTE"]) == "New Palette 2")
        #expect(Library.uniqueName("New Palette", among: ["New Palette", "New Palette 2", "new palette 3"]) == "New Palette 4")
        #expect(Library.uniqueName("New Palette", among: ["New Palette 2"]) == "New Palette")
    }

    @Test func editsThatChangeNothingKeepModifiedAt() throws {
        var (library, palette, group) = try sampleLibrary()
        let before = library
        let red = try #require(library.palette(palette)?.ungrouped.first)
        try library.renamePalette(palette, to: "P", at: t1)
        try library.renameGroup(group, in: palette, to: "G", at: t1)
        try library.setIcon(nil, of: palette, at: t1)
        try library.renameSwatch(red.id, in: .ungrouped(palette), to: red.name, at: t1)
        #expect(library == before)
    }

    @Test func movePaletteBefore() {
        var library = Library()
        let ids = ["A", "B", "C", "D"].map { library.createPalette(name: $0, at: t0) }
        library.movePalette(ids[0], before: ids[2])
        #expect(library.palettes.map(\.id) == [ids[1], ids[0], ids[2], ids[3]])
        library.movePalette(ids[3], before: ids[1])
        #expect(library.palettes.map(\.id) == [ids[3], ids[1], ids[0], ids[2]])
        library.movePalette(ids[3], before: nil)
        #expect(library.palettes.map(\.id) == [ids[1], ids[0], ids[2], ids[3]])
        let unchanged = library
        library.movePalette(ids[0], before: ids[0])
        library.movePalette(ids[0], before: ids[2])
        library.movePalette(UUID(), before: ids[0])
        library.movePalette(ids[0], before: UUID())
        #expect(library == unchanged)
    }
}
