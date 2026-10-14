import Foundation
import Testing
@testable import ColorsipCore

@Suite("Undo and redo")
struct UndoableLibraryTests {
    @Test func undoAndRedo() throws {
        var undoable = UndoableLibrary()
        #expect(!undoable.canUndo && !undoable.canRedo)
        let id = undoable.perform("New Palette") { $0.createPalette(name: "A", at: t0) }
        try undoable.perform("Rename Palette") { l throws(LibraryError) in try l.renamePalette(id, to: "B", at: t1) }
        #expect(undoable.undoActionName == "Rename Palette")

        do { let ok = undoable.undo(); #expect(ok) }
        #expect(undoable.library.palette(id)?.name == "A")
        #expect(undoable.undoActionName == "New Palette")
        #expect(undoable.redoActionName == "Rename Palette")

        do { let ok = undoable.undo(); #expect(ok) }
        #expect(undoable.library.palettes.isEmpty)
        #expect(!undoable.canUndo)
        do { let ok = undoable.undo(); #expect(!ok) }

        do { let ok = undoable.redo(); #expect(ok) }
        do { let ok = undoable.redo(); #expect(ok) }
        #expect(undoable.library.palette(id)?.name == "B")
        #expect(!undoable.canRedo)
        do { let ok = undoable.redo(); #expect(!ok) }
    }

    @Test func failedChangeIsNotRecorded() throws {
        var undoable = UndoableLibrary()
        let id = undoable.perform("New Palette") { $0.createPalette(name: "A", at: t0) }
        #expect(throws: LibraryError.notFound) {
            try undoable.perform("Rename") { l throws(LibraryError) in
                try l.renamePalette(id, to: "B", at: t1)
                try l.renamePalette(UUID(), to: "C", at: t1)
            }
        }
        #expect(undoable.library.palette(id)?.name == "A")
        #expect(undoable.undoActionName == "New Palette")
    }

    @Test func noOpIsNotRecorded() {
        var undoable = UndoableLibrary()
        undoable.perform("Nothing") { _ in }
        #expect(!undoable.canUndo)
    }

    @Test func newChangeClearsRedo() {
        var undoable = UndoableLibrary()
        undoable.perform("A") { _ = $0.createPalette(name: "A", at: t0) }
        undoable.undo()
        #expect(undoable.canRedo)
        undoable.perform("B") { _ = $0.createPalette(name: "B", at: t0) }
        #expect(!undoable.canRedo)
    }

    @Test func undoRestoresPickTargetWithLock() throws {
        var undoable = UndoableLibrary()
        let id = undoable.perform("New") { $0.createPalette(name: "A", at: t0) }
        try undoable.perform("Target") { l throws(LibraryError) in try l.setPickTarget(id) }
        try undoable.perform("Lock") { l throws(LibraryError) in try l.setLocked(true, palette: id, at: t1) }
        #expect(undoable.library.pickTarget == nil)
        undoable.undo()
        #expect(undoable.library.pickTarget == id)
        #expect(undoable.library.palette(id)?.isLocked == false)
    }

    @Test func limitDropsOldestLevels() {
        var undoable = UndoableLibrary(limit: 3)
        for i in 0..<5 {
            undoable.perform("Step \(i)") { _ = $0.createPalette(name: "\(i)", at: t0) }
        }
        var undone = 0
        while undoable.undo() { undone += 1 }
        #expect(undone == 3)
        #expect(undoable.library.palettes.map(\.name) == ["0", "1"])
        #expect(UndoableLibrary.defaultLimit == 100)
    }

    @Test func replaceResetsStacks() {
        var undoable = UndoableLibrary()
        undoable.perform("A") { _ = $0.createPalette(name: "A", at: t0) }
        undoable.replace(with: Library())
        #expect(!undoable.canUndo && !undoable.canRedo)
        #expect(undoable.library.palettes.isEmpty)
    }
}
