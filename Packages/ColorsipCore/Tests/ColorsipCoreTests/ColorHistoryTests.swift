import Foundation
import Testing
@testable import ColorsipCore

private let date = Date(timeIntervalSince1970: 1_800_000_000)

/// A distinct color for each `i` in 0..<72: hues 5° apart.
private func color(_ i: Int) -> CSipColor {
    CSipColor(.oklch, 0.6, 0.1, Double(i) * 5)
}

private func decode(_ json: String) throws -> ColorHistory {
    try JSONDecoder.library.decode(ColorHistory.self, from: Data(json.utf8))
}

/// A history store in a fresh temporary library folder.
private struct TempFolder {
    let root = FileManager.default.temporaryDirectory.appending(path: "ColorsipTests-\(UUID().uuidString)")
    var store: LibraryStore { LibraryStore(folder: root.appending(path: "Library")) }
    var historyURL: URL { store.folder.appending(path: "history.json") }

    func write(_ string: String) throws {
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Data(string.utf8).write(to: historyURL)
    }
    func contents() throws -> String { String(decoding: try Data(contentsOf: historyURL), as: UTF8.self) }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Color History")
struct ColorHistoryTests {
    @Test func startsEmpty() {
        #expect(ColorHistory().swatches.isEmpty)
    }

    @Test func recordsNewestFirst() {
        var history = ColorHistory()
        history.record(color(1), name: "One", at: date)
        history.record(color(2), name: "Two", at: date.addingTimeInterval(1))
        #expect(history.swatches.map(\.name) == ["Two", "One"])
        #expect(history.swatches[0].color == color(2))
        #expect(history.swatches[0].createdAt == date.addingTimeInterval(1))
    }

    @Test func keepsTheSixteenNewest() {
        var history = ColorHistory()
        for i in 0..<17 { history.record(color(i), name: "\(i)", at: date) }
        #expect(ColorHistory.capacity == 16)
        #expect(history.swatches.map(\.name) == (1..<17).reversed().map { "\($0)" })
    }

    @Test func rePickingMovesTheColorToTheFrontWithTheNewValue() {
        var history = ColorHistory()
        history.record(color(1), name: "One", at: date)
        history.record(color(2), name: "Two", at: date)
        history.record(color(3), name: "Three", at: date)
        let nearlyOne = CSipColor(.oklch, 0.6, 0.1, 5.01)
        let later = date.addingTimeInterval(5)
        history.record(nearlyOne, name: "One again", at: later)
        #expect(history.swatches.map(\.name) == ["One again", "Three", "Two"])
        #expect(history.swatches[0].color == nearlyOne)
        #expect(history.swatches[0].createdAt == later)
    }

    @Test func rePickingTheFrontColorUpdatesIt() {
        var history = ColorHistory()
        history.record(color(1), name: "One", at: date)
        let before = history
        history.record(color(1), name: "One", at: date.addingTimeInterval(1))
        #expect(history.swatches.count == 1)
        #expect(history != before)
    }

    @Test func perceptuallyEqualColorsInOtherSpacesMerge() {
        var history = ColorHistory()
        let red = CSipColor(.srgb, 1, 0, 0)
        history.record(red, name: "Red", at: date)
        history.record(red.converted(to: .displayP3), name: "Red P3", at: date)
        #expect(history.swatches.map(\.name) == ["Red P3"])
    }

    @Test func initNormalizesDuplicatesAndCapacity() {
        let swatches = (0..<20).map { Swatch(color: color($0), name: "\($0)", createdAt: date) }
        let duplicate = Swatch(color: color(0), name: "dup", createdAt: date)
        let history = ColorHistory(swatches: [swatches[0], duplicate] + swatches.dropFirst())
        #expect(history.swatches.count == 16)
        #expect(history.swatches.map(\.name) == (0..<16).map { "\($0)" })
    }

    @Test func roundTripsThroughJSON() throws {
        var history = ColorHistory()
        history.record(CSipColor(.displayP3, 0.2364, 0.2353, 0.8588), name: "Blue", at: date)
        history.record(color(5), name: "Five", at: date)
        let data = try JSONEncoder.library.encode(history)
        #expect(try JSONDecoder.library.decode(ColorHistory.self, from: data) == history)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""formatVersion" : 1"#))
        #expect(json.contains(#""swatches""#))
    }

    @Test func newerFormatIsRejected() {
        #expect(throws: ColorsipFormatError.newerFormat(2)) {
            try decode(#"{ "formatVersion": 2, "swatches": [] }"#)
        }
    }

    @Test func badEntriesAreSkipped() throws {
        let history = try decode(
            """
            { "formatVersion": 1, "swatches": [
              { "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Red",
                "color": { "colorSpace": "srgb", "components": [1, 0, 0], "alpha": 1 },
                "createdAt": "2027-01-15T08:00:00.000Z", "modifiedAt": "2027-01-15T08:00:00.000Z" },
              { "id": "nope" },
              { "id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Odd",
                "color": { "colorSpace": "srgb", "components": [1, 0], "alpha": 1 },
                "createdAt": "2027-01-15T08:00:00.000Z", "modifiedAt": "2027-01-15T08:00:00.000Z" }
            ] }
            """)
        #expect(history.swatches.map(\.name) == ["Red"])
    }

    @Test func missingSwatchesGiveAnEmptyHistory() throws {
        #expect(try decode(#"{ "formatVersion": 1 }"#).swatches.isEmpty)
    }
}

@Suite("Color History controller")
@MainActor
struct ColorHistoryControllerTests {
    @Test func missingFileGivesAnEmptyHistory() {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        let controller = ColorHistoryController(store: temp.store)
        #expect(controller.history.swatches.isEmpty)
        #expect(controller.loadIssue == nil)
        #expect(!FileManager.default.fileExists(atPath: temp.historyURL.path))
    }

    @Test func recordSavesAndReloads() throws {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        let controller = ColorHistoryController(store: temp.store)
        controller.record(color(1), name: "One", at: date)
        controller.record(color(2), name: "Two", at: date)
        #expect(controller.lastError == nil)
        #expect(ColorHistoryController(store: temp.store).history == controller.history)
    }

    @Test func corruptFileIsReportedAndNeverOverwritten() throws {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        try temp.write("not json")
        let controller = ColorHistoryController(store: temp.store)
        #expect(controller.loadIssue == .unreadable(file: "history.json"))
        controller.record(color(1), name: "One", at: date)
        #expect(controller.history.swatches.map(\.name) == ["One"]) // works for this session
        #expect(try temp.contents() == "not json")
    }

    @Test func newerFileIsReportedAndNeverOverwritten() throws {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        let newer = #"{ "formatVersion": 3, "swatches": [] }"#
        try temp.write(newer)
        let controller = ColorHistoryController(store: temp.store)
        #expect(controller.loadIssue == .newerFormat(file: "history.json", version: 3))
        controller.record(color(1), name: "One", at: date)
        #expect(try temp.contents() == newer)
    }

    @Test func failedSaveKeepsThePickAndRecordsTheError() throws {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        // A file where the library folder should be makes the write fail.
        try FileManager.default.createDirectory(at: temp.root, withIntermediateDirectories: true)
        try Data().write(to: temp.store.folder)
        let controller = ColorHistoryController(store: temp.store)
        controller.record(color(1), name: "One", at: date)
        #expect(controller.history.swatches.count == 1)
        #expect(controller.lastError != nil)
    }

    @Test func undoingLibraryChangesLeavesHistoryAlone() {
        let temp = TempFolder()
        defer { temp.cleanUp() }
        let library = LibraryController(store: temp.store)
        let history = ColorHistoryController(store: temp.store)
        library.perform("New Palette") { $0.createPalette(name: "P", at: date) }
        history.record(color(1), name: "One", at: date)
        library.undo()
        #expect(history.history.swatches.map(\.name) == ["One"])
        #expect(ColorHistoryController(store: temp.store).history.swatches.map(\.name) == ["One"])
    }
}
