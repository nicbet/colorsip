import Foundation
import Testing
@testable import ColorsipCore

private let date = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
@Suite("Library controller")
struct LibraryControllerTests {
    @Test func missingFolderLoadsAnEmptyLibrary() {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        let controller = LibraryController(store: temp.store)
        #expect(controller.library.palettes.isEmpty)
        #expect(controller.loadIssues.isEmpty)
        #expect(controller.lastError == nil)
    }

    @Test func loadsWhatIsOnDisk() throws {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        var library = Library()
        let a = library.createPalette(name: "A", at: date)
        let b = library.createPalette(name: "B", at: date)
        try library.setPickTarget(b)
        try temp.store.save(library, previous: nil)

        let controller = LibraryController(store: temp.store)
        #expect(controller.library.palettes.map(\.id) == [a, b])
        #expect(controller.library.pickTarget == b)
    }

    @Test func performSavesTheChange() throws {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        let controller = LibraryController(store: temp.store)
        let id = controller.perform("New Palette") { $0.createPalette(name: "Brand", at: date) }
        try controller.perform("Set Pick Target") { library throws(LibraryError) in try library.setPickTarget(id) }

        let reloaded = temp.store.load().library
        #expect(reloaded.palettes.map(\.name) == ["Brand"])
        #expect(reloaded.pickTarget == id)
        #expect(controller.undoActionName == "Set Pick Target")
    }

    @Test func undoAndRedoSave() {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        let controller = LibraryController(store: temp.store)
        controller.perform("New Palette") { $0.createPalette(name: "Brand", at: date) }

        #expect(controller.canUndo)
        controller.undo()
        #expect(controller.library.palettes.isEmpty)
        #expect(temp.store.load().library.palettes.isEmpty)

        #expect(controller.canRedo)
        controller.redo()
        #expect(controller.library.palettes.map(\.name) == ["Brand"])
        #expect(temp.store.load().library.palettes.map(\.name) == ["Brand"])
    }

    @Test func aFailedChangeLeavesTheLibraryAlone() throws {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        let controller = LibraryController(store: temp.store)
        let id = controller.perform("New Palette") { $0.createPalette(name: "Locked", at: date) }
        try controller.perform("Lock") { library throws(LibraryError) in try library.setLocked(true, palette: id, at: date) }
        let before = controller.library

        #expect(throws: LibraryError.locked(id)) {
            try controller.perform("Set Pick Target") { library throws(LibraryError) in try library.setPickTarget(id) }
        }
        #expect(controller.library == before)
        #expect(controller.undoActionName == "Lock")
    }

    @Test func saveErrorsAreReportedAndClearedBySuccess() throws {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        // A file where the library folder should be makes every save fail.
        try FileManager.default.createDirectory(at: temp.root, withIntermediateDirectories: true)
        try Data().write(to: temp.store.folder)

        let controller = LibraryController(store: temp.store)
        controller.perform("New Palette") { $0.createPalette(name: "Brand", at: date) }
        #expect(controller.lastError != nil)
        #expect(controller.library.palettes.count == 1)

        try FileManager.default.removeItem(at: temp.store.folder)
        controller.perform("New Palette") { $0.createPalette(name: "Other", at: date) }
        #expect(controller.lastError == nil)
        #expect(temp.store.load().library.palettes.map(\.name) == ["Brand", "Other"])
    }

    @Test func reportsLoadIssues() throws {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        try FileManager.default.createDirectory(at: temp.store.folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: temp.store.folder.appending(path: "library.json"))

        let controller = LibraryController(store: temp.store)
        #expect(controller.loadIssues == [.unreadable(file: "library.json")])
    }
}
