import Foundation
import Testing
@testable import ColorsipCore

@MainActor
private final class FakeClipboard: Clipboard {
    var strings: [String] = []
    func setString(_ string: String) { strings.append(string) }
}

/// A controller over a fresh temporary library with palette "P" (red and green, ungrouped; group
/// "G" with blue) as the pick target, and a history in the same folder.
@MainActor
private func routing(target: Bool = true) throws -> (LibraryController, ColorHistoryController, TempLibrary, Palette.ID) {
    let temp = TempLibrary()
    var (library, palette, _) = try sampleLibrary()
    if target { try library.setPickTarget(palette) }
    try temp.store.save(library, previous: nil)
    return (LibraryController(store: temp.store), ColorHistoryController(store: temp.store), temp, palette)
}

private let pickColor = CSipColor(.srgb, 60 / 255.0, 60 / 255.0, 219 / 255.0)

@MainActor
@Suite("Pick routing")
struct PickRoutingTests {
    @Test func addPickGoesToTheFrontOfTheTargetsUngroupedSection() throws {
        let (library, _, temp, palette) = try routing()
        defer { temp.cleanUp() }
        let id = try #require(library.addPick(pickColor, name: "Blue Pick", at: t1))
        let p = try #require(library.library.palette(palette))
        #expect(p.ungrouped.map(\.id).first == id)
        #expect(p.ungrouped.map(\.name) == ["Blue Pick", "Red", "Green"])
        #expect(p.ungrouped[0].createdAt == t1)
        #expect(p.groups[0].swatches.map(\.name) == ["Blue"])
        #expect(library.undoActionName == "Pick Color")
        #expect(temp.store.load().library.palette(palette)?.ungrouped.first?.id == id)
    }

    @Test func addPickWithoutATargetChangesNothing() throws {
        let (library, _, temp, _) = try routing(target: false)
        defer { temp.cleanUp() }
        #expect(library.addPick(pickColor, name: "Blue Pick", at: t1) == nil)
        #expect(!library.canUndo)
    }

    @Test func addPickRefusesADuplicate() throws {
        let (library, _, temp, palette) = try routing()
        defer { temp.cleanUp() }
        #expect(library.addPick(almostRedColor, name: "Red Again", at: t1) == nil)
        #expect(library.library.palette(palette)?.ungrouped.count == 2)
        #expect(!library.canUndo)
        // Blue is only in group G, so it's not a duplicate of the ungrouped section.
        #expect(library.addPick(blueColor, name: "Blue", at: t1) != nil)
    }

    @Test func lockingTheTargetClearsItSoPicksSkipIt() throws {
        let (library, _, temp, palette) = try routing()
        defer { temp.cleanUp() }
        library.setLocked(true, palette: palette)
        #expect(library.addPick(pickColor, name: "Blue Pick", at: t1) == nil)
        #expect(library.library.palette(palette)?.ungrouped.count == 2)
    }

    @Test func routePickRecordsHistoryAddsToTheTargetAndCopies() throws {
        let (library, history, temp, palette) = try routing()
        defer { temp.cleanUp() }
        let clipboard = FakeClipboard()
        routePick(pickColor, format: .cssHex, history: history, library: library, clipboard: clipboard, at: t1)
        let name = pickColor.friendlyName
        #expect(history.history.swatches.map(\.name) == [name])
        #expect(library.library.palette(palette)?.ungrouped.first?.name == name)
        #expect(clipboard.strings == ["#3c3cdb"])
    }

    @Test func routePickWithoutATargetStillRecordsAndCopies() throws {
        let (library, history, temp, _) = try routing(target: false)
        defer { temp.cleanUp() }
        let clipboard = FakeClipboard()
        routePick(pickColor, format: .cssRGB, history: history, library: library, clipboard: clipboard, at: t1)
        #expect(history.history.swatches.count == 1)
        #expect(clipboard.strings == ["rgb(60 60 219)"])
    }

    @Test func eachPickIsItsOwnUndoStepAndUndoLeavesHistoryAlone() throws {
        let (library, history, temp, palette) = try routing()
        defer { temp.cleanUp() }
        let clipboard = FakeClipboard()
        routePick(pickColor, format: .cssHex, history: history, library: library, clipboard: clipboard, at: t1)
        routePick(blueColor, format: .cssHex, history: history, library: library, clipboard: clipboard, at: t2)
        #expect(library.library.palette(palette)?.ungrouped.count == 4)
        #expect(clipboard.strings.last == "#0000ff")

        library.undo()
        #expect(library.library.palette(palette)?.ungrouped.count == 3)
        library.undo()
        #expect(library.library.palette(palette)?.ungrouped.count == 2)
        #expect(history.history.swatches.count == 2)
    }
}

private let figma = PasteTarget(pid: 42, bundleID: "com.figma.Desktop")
private let xcode = PasteTarget(pid: 43, bundleID: "com.apple.dt.Xcode")
private let colorsip = PasteTarget(pid: 1, bundleID: "com.nicolas-bettenburg.colorsip")

@MainActor
@Suite("Cmd+click paste")
struct PastePickTests {
    @Test func theTargetIsTheFrontmostAppWhenItIsntColorsip() {
        var tracker = PasteTargetTracker(ownBundleID: colorsip.bundleID)
        tracker.activated(figma)
        #expect(tracker.target(frontmost: xcode) == xcode)
    }

    @Test func whenColorsipIsFrontmostTheTargetIsTheLastOtherAppActivated() {
        var tracker = PasteTargetTracker(ownBundleID: colorsip.bundleID)
        tracker.activated(figma)
        tracker.activated(xcode)
        tracker.activated(colorsip)
        #expect(tracker.target(frontmost: colorsip) == xcode)
    }

    @Test func noTargetBeforeAnyOtherAppWasActivated() {
        var tracker = PasteTargetTracker(ownBundleID: colorsip.bundleID)
        tracker.activated(colorsip)
        #expect(tracker.target(frontmost: colorsip) == nil)
        #expect(tracker.target(frontmost: nil) == nil)
    }

    @Test func pastesWithAccessibilityAndCopiesInTheTargetsFormat() throws {
        let (library, history, temp, palette) = try routing()
        defer { temp.cleanUp() }
        let clipboard = FakeClipboard()
        var askedFor: [String?] = []
        let plan = routePastePick(
            pickColor, into: figma, accessibilityGranted: true,
            formatForApp: { askedFor.append($0); return .cssRGB },
            history: history, library: library, clipboard: clipboard, at: t1)
        #expect(plan == .paste(figma))
        #expect(askedFor == ["com.figma.Desktop"])
        #expect(clipboard.strings == ["rgb(60 60 219)"])
        #expect(history.history.swatches.count == 1)
        #expect(library.library.palette(palette)?.ungrouped.first?.name == pickColor.friendlyName)
    }

    @Test func withoutAccessibilityItOnlyCopiesAndAsksForThePermission() throws {
        let (library, history, temp, _) = try routing()
        defer { temp.cleanUp() }
        let clipboard = FakeClipboard()
        let plan = routePastePick(
            pickColor, into: figma, accessibilityGranted: false, formatForApp: { _ in .cssHex },
            history: history, library: library, clipboard: clipboard, at: t1)
        #expect(plan == .needsAccessibility)
        #expect(clipboard.strings == ["#3c3cdb"])
        #expect(history.history.swatches.count == 1)
    }

    @Test func withoutATargetItOnlyCopiesWithoutAsking() throws {
        let (library, history, temp, _) = try routing()
        defer { temp.cleanUp() }
        let clipboard = FakeClipboard()
        var askedFor: [String?] = []
        let plan = routePastePick(
            pickColor, into: nil, accessibilityGranted: false,
            formatForApp: { askedFor.append($0); return .cssHex },
            history: history, library: library, clipboard: clipboard, at: t1)
        #expect(plan == .copyOnly)
        #expect(askedFor == [nil])
        #expect(clipboard.strings == ["#3c3cdb"])
    }
}
