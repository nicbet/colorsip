import Foundation
import Testing
@testable import ColorsipCore

/// A controller over a temporary library with palette "P": red and green ungrouped, blue in "G".
@MainActor
private func controller() throws -> (LibraryController, TempLibrary, palette: Palette.ID, red: Swatch.ID) {
    let temp = TempLibrary()
    let (library, palette, _) = try sampleLibrary()
    try temp.store.save(library, previous: nil)
    let controller = LibraryController(store: temp.store)
    let red = try #require(controller.library.palette(palette)?.ungrouped.first { $0.name == "Red" }?.id)
    return (controller, temp, palette, red)
}

@Suite("Library: edit swatch")
struct LibraryEditSwatchTests {
    @Test func appliesColorNameAndDescriptionAtOnce() throws {
        var (library, palette, _) = try sampleLibrary()
        let red = try #require(library.palette(palette)?.ungrouped.first { $0.name == "Red" })
        let orange = CSipColor(.srgb, 1, 0.5, 0)
        try library.editSwatch(red.id, in: .ungrouped(palette), color: orange, name: "Orange", description: "Warm", at: t1)
        let edited = try #require(library.palette(palette)?.ungrouped.first { $0.id == red.id })
        #expect(edited.color == orange && edited.name == "Orange" && edited.description == "Warm")
        #expect(edited.modifiedAt == t1 && edited.createdAt == t0)
    }

    @Test func refusesADuplicateInTheSectionAndChangesNothing() throws {
        var (library, palette, _) = try sampleLibrary()
        let swatches = try #require(library.palette(palette)?.ungrouped)
        let red = try #require(swatches.first { $0.name == "Red" })
        let green = try #require(swatches.first { $0.name == "Green" })
        let before = library
        expectError(.duplicate(existing: green.id)) {
            try library.editSwatch(red.id, in: .ungrouped(palette), color: greenColor, name: "X", description: nil, at: t1)
        }
        #expect(library == before)
    }

    @Test func refusesLockedPalettes() throws {
        var (library, palette, _) = try sampleLibrary()
        let red = try #require(library.palette(palette)?.ungrouped.first)
        try library.setLocked(true, palette: palette, at: t0)
        expectError(.locked(palette)) {
            try library.editSwatch(red.id, in: .ungrouped(palette), color: blueColor, name: "X", description: nil, at: t1)
        }
    }
}

@MainActor
@Suite("Library commands: edit swatch")
struct EditSwatchCommandTests {
    @Test func oneUndoStepRestoresEverything() throws {
        let (controller, temp, palette, red) = try controller()
        defer { temp.cleanUp() }
        let section = SectionID.ungrouped(palette)
        let orange = CSipColor(.srgb, 1, 0.5, 0)
        #expect(controller.editSwatch(red, in: section, color: orange, name: " Orange ", description: " Warm ", at: t1) == .changed)
        #expect(controller.undoActionName == "Edit Color")
        var swatch = try #require(controller.library.palette(palette)?.ungrouped.first { $0.id == red })
        #expect(swatch.color == orange && swatch.name == "Orange" && swatch.description == "Warm")
        #expect(temp.store.load().library == controller.library)

        controller.undo()
        swatch = try #require(controller.library.palette(palette)?.ungrouped.first { $0.id == red })
        #expect(swatch.color == redColor && swatch.name == "Red" && swatch.description == nil)
        #expect(!controller.canUndo)
    }

    @Test func emptyNameKeepsTheOldNameAndEmptyDescriptionClearsIt() throws {
        let (controller, temp, palette, red) = try controller()
        defer { temp.cleanUp() }
        let section = SectionID.ungrouped(palette)
        controller.editSwatch(red, in: section, color: redColor, name: "Red", description: "Hot")
        #expect(controller.editSwatch(red, in: section, color: redColor, name: "  ", description: " ") == .changed)
        let swatch = try #require(controller.library.palette(palette)?.ungrouped.first { $0.id == red })
        #expect(swatch.name == "Red" && swatch.description == nil)
    }

    @Test func nothingChangedRecordsNoStep() throws {
        let (controller, temp, palette, red) = try controller()
        defer { temp.cleanUp() }
        #expect(controller.editSwatch(red, in: .ungrouped(palette), color: redColor, name: "Red", description: "") == .unchanged)
        #expect(!controller.canUndo)
    }

    @Test func duplicateAndMissingAreReported() throws {
        let (controller, temp, palette, red) = try controller()
        defer { temp.cleanUp() }
        let green = try #require(controller.library.palette(palette)?.ungrouped.first { $0.name == "Green" }?.id)
        #expect(controller.editSwatch(red, in: .ungrouped(palette), color: greenColor, name: "Red", description: nil)
            == .duplicate(existing: green))
        #expect(controller.editSwatch(UUID(), in: .ungrouped(palette), color: greenColor, name: "Red", description: nil)
            == .failed)
        #expect(!controller.canUndo)
    }

    @Test func savesTheEditorsDraft() throws {
        let (controller, temp, palette, red) = try controller()
        defer { temp.cleanUp() }
        let swatch = try #require(controller.library.palette(palette)?.ungrouped.first { $0.id == red })
        var editor = ColorEditor(swatch: swatch)
        editor.setPicked(CSipColor(.srgb, 1, 0.5, 0))
        editor.setName("Orange")
        #expect(controller.save(editor, in: .ungrouped(palette)) == .changed)
        let saved = try #require(controller.library.palette(palette)?.ungrouped.first { $0.id == red })
        #expect(saved.color == editor.color && saved.name == "Orange")
    }
}

@Suite("Edit menu and editor settings")
struct EditMenuTests {
    @Test func editComesAfterCopyAsInUnlockedPalettesOnly() throws {
        var (library, palette, g) = try sampleLibrary()
        let p = try #require(library.palette(palette))
        #expect(SwatchMenuItem.items(in: nil, of: p) == [.copyAs, .edit, .rename, .delete])
        #expect(SwatchMenuItem.items(in: g, of: p) == [.copyAs, .edit, .rename, .delete, .group])
        #expect(SwatchMenuItem.items(in: nil, of: nil) == [.copyAs])
        try library.setLocked(true, palette: palette, at: t0)
        #expect(SwatchMenuItem.items(in: g, of: try #require(library.palette(palette))) == [.copyAs])
    }

    @Test func remembersTheEditorModel() throws {
        let temp = try TemporaryDefaults()
        #expect(temp.localSettings.editorModel == .hex)
        temp.localSettings.editorModel = .oklch
        #expect(temp.localSettings.editorModel == .oklch)
        temp.defaults.set("cmyk", forKey: "editorModel")
        #expect(temp.localSettings.editorModel == .hex)
    }
}
