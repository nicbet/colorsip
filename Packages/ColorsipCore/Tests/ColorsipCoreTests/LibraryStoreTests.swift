import Foundation
import Testing
@testable import ColorsipCore

/// A store in a fresh temporary folder, removed when the test's `defer` runs `cleanUp`.
private struct TempStore {
    let root = FileManager.default.temporaryDirectory.appending(path: "ColorsipTests-\(UUID().uuidString)")
    var store: LibraryStore { LibraryStore(folder: root.appending(path: "Library")) }
    var folder: URL { store.folder }

    func paletteURL(_ id: Palette.ID) -> URL { folder.appending(path: "palettes/\(id.uuidString).colorsip") }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func write(_ string: String, to relativePath: String) throws {
        let url = folder.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: url)
    }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

/// Two palettes, the second one the pick target.
private func twoPalettes() throws -> Library {
    var (library, _, _) = try sampleLibrary()
    let q = library.createPalette(name: "Q", at: t1)
    try library.setPickTarget(q)
    return library
}

@Suite("Library store")
struct LibraryStoreTests {
    @Test func missingFolderLoadsEmpty() {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let result = temp.store.load()
        #expect(result.library == Library())
        #expect(result.issues.isEmpty)
    }

    @Test func defaultFolder() {
        #expect(LibraryStore.defaultFolder.path.hasSuffix("Library/Application Support/Colorsip/Library"))
    }

    @Test func roundTrip() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let library = try twoPalettes()
        try temp.store.save(library, previous: nil)
        #expect(temp.exists(temp.folder.appending(path: "library.json")))
        for palette in library.palettes { #expect(temp.exists(temp.paletteURL(palette.id))) }
        let result = temp.store.load()
        #expect(result.library == library)
        #expect(result.issues.isEmpty)
    }

    @Test func libraryJSONShape() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let library = try twoPalettes()
        try temp.store.save(library, previous: nil)
        let data = try Data(contentsOf: temp.folder.appending(path: "library.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["formatVersion"] as? Int == 1)
        #expect(json["paletteOrder"] as? [String] == library.palettes.map(\.id.uuidString))
        #expect(json["pickTarget"] as? String == library.pickTarget?.uuidString)
    }

    @Test func savesOnlyWhatChanged() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let library = try twoPalettes()
        let (p, q) = (library.palettes[0].id, library.palettes[1].id)
        try temp.store.save(library, previous: nil)
        // Remove files behind the store's back: they are only rewritten if they changed.
        try FileManager.default.removeItem(at: temp.paletteURL(q))
        try FileManager.default.removeItem(at: temp.folder.appending(path: "library.json"))
        var changed = library
        try changed.renamePalette(p, to: "Renamed", at: t2)
        try temp.store.save(changed, previous: library)
        #expect(!temp.exists(temp.paletteURL(q)))
        #expect(!temp.exists(temp.folder.appending(path: "library.json")))
        let decoded = try ColorsipPaletteFormat.decode(Data(contentsOf: temp.paletteURL(p)))
        #expect(decoded.name == "Renamed")

        var reordered = changed
        reordered.movePalettes(fromOffsets: [1], toOffset: 0)
        try temp.store.save(reordered, previous: changed)
        #expect(temp.exists(temp.folder.appending(path: "library.json")))
    }

    @Test func deletedPalettesLoseTheirFiles() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let library = try twoPalettes()
        let p = library.palettes[0].id
        try temp.store.save(library, previous: nil)
        var changed = library
        try changed.deletePalette(p)
        try temp.store.save(changed, previous: library)
        #expect(!temp.exists(temp.paletteURL(p)))
        #expect(temp.store.load().library == changed)
    }

    @Test func corruptPaletteIsReportedAndKept() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let library = try twoPalettes()
        try temp.store.save(library, previous: nil)
        let bad = library.palettes[0].id
        try temp.write("garbage", to: "palettes/\(bad.uuidString).colorsip")
        let result = temp.store.load()
        #expect(result.library.palettes.map(\.id) == [library.palettes[1].id])
        #expect(result.issues == [.unreadable(file: "palettes/\(bad.uuidString).colorsip")])
        // Saving the loaded library leaves the corrupt file alone.
        var changed = result.library
        try changed.renamePalette(library.palettes[1].id, to: "Q2", at: t2)
        try temp.store.save(changed, previous: result.library)
        #expect(try String(contentsOf: temp.paletteURL(bad), encoding: .utf8) == "garbage")
    }

    @Test func newerPaletteFormatIsReportedAndKept() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let library = try twoPalettes()
        try temp.store.save(library, previous: nil)
        let newer = library.palettes[0].id
        let url = temp.paletteURL(newer)
        let text = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: #""formatVersion" : 1"#, with: #""formatVersion" : 7"#)
        try Data(text.utf8).write(to: url)
        let result = temp.store.load()
        #expect(result.library.palettes.map(\.id) == [library.palettes[1].id])
        #expect(result.issues == [.newerFormat(file: "palettes/\(newer.uuidString).colorsip", version: 7)])
        try temp.store.save(result.library, previous: nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == text)
    }

    @Test func newerLibraryIndexIsReportedAndKept() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let library = try twoPalettes()
        try temp.store.save(library, previous: nil)
        let index = #"{ "formatVersion": 9, "paletteOrder": [] }"#
        try temp.write(index, to: "library.json")
        let result = temp.store.load()
        #expect(result.issues == [.newerFormat(file: "library.json", version: 9)])
        #expect(Set(result.library.palettes.map(\.id)) == Set(library.palettes.map(\.id)))
        var changed = result.library
        changed.movePalettes(fromOffsets: [0], toOffset: 2)
        try temp.store.save(changed, previous: result.library)
        let kept = try String(contentsOf: temp.folder.appending(path: "library.json"), encoding: .utf8)
        #expect(kept == index)
    }

    @Test func unlistedPalettesAreAppendedAndMissingOnesDropped() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let library = try twoPalettes()
        try temp.store.save(library, previous: nil)
        let (p, q) = (library.palettes[0].id, library.palettes[1].id)
        let ghost = UUID()
        try temp.write(
            #"{ "formatVersion": 1, "paletteOrder": ["\#(q.uuidString)", "\#(ghost.uuidString)"] }"#,
            to: "library.json")
        let result = temp.store.load()
        #expect(result.library.palettes.map(\.id) == [q, p])
        #expect(result.library.pickTarget == nil)
        #expect(result.issues.isEmpty)
    }

    @Test func missingOrLockedPickTargetIsCleared() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        var library = Library()
        var palette = Palette(name: "Locked", at: t0)
        palette.isLocked = true
        library = Library(palettes: [palette])
        try temp.store.save(library, previous: nil)
        try temp.write(
            #"{ "formatVersion": 1, "paletteOrder": ["\#(palette.id.uuidString)"], "pickTarget": "\#(palette.id.uuidString)" }"#,
            to: "library.json")
        #expect(temp.store.load().library.pickTarget == nil)
    }

    @Test func idInsideTheFileWins() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        let palette = Palette(name: "A", at: t0)
        try temp.write(
            String(decoding: ColorsipPaletteFormat.encode(palette), as: UTF8.self),
            to: "palettes/\(UUID().uuidString).colorsip")
        #expect(temp.store.load().library.palettes.map(\.id) == [palette.id])
    }

    @Test func otherFilesInPalettesFolderAreIgnored() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        try temp.write("x", to: "palettes/notes.txt")
        try temp.write("x", to: "palettes/\(UUID().uuidString).conflict-2026.colorsip")
        let result = temp.store.load()
        #expect(result.library.palettes.isEmpty && result.issues.isEmpty)
    }

    @Test func auxiliaryFiles() throws {
        let temp = TempStore()
        defer { temp.cleanUp() }
        #expect(try temp.store.load([String].self, from: .history) == nil)
        try temp.store.save(["a", "b"], to: .history)
        #expect(try temp.store.load([String].self, from: .history) == ["a", "b"])
        try temp.store.save(["k": 1], to: .settings)
        #expect(temp.exists(temp.folder.appending(path: "settings.json")))
        #expect(LibraryFile.history.rawValue == "history.json")
    }
}
