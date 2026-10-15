import Foundation
import Testing
@testable import ColorsipCore

@Suite("Library menus")
struct LibraryMenusTests {
    @Test func unlockedPaletteMenu() throws {
        let (library, palette, _) = try sampleLibrary()
        let p = try #require(library.palette(palette))
        #expect(PaletteMenuItem.items(for: p) == [
            .rename, .editDescription, .setIcon, .lock, .newGroup, .groups, .duplicate, .delete,
        ])
    }

    @Test func paletteMenuWithoutGroupsLeavesOutGroups() {
        let p = Palette(name: "P", at: t0)
        #expect(PaletteMenuItem.items(for: p) == [
            .rename, .editDescription, .setIcon, .lock, .newGroup, .duplicate, .delete,
        ])
    }

    @Test func lockedPaletteOnlyOffersUnlock() throws {
        var (library, palette, _) = try sampleLibrary()
        try library.setLocked(true, palette: palette, at: t0)
        let p = try #require(library.palette(palette))
        #expect(PaletteMenuItem.items(for: p) == [.unlock])
    }

    @Test func groupMenuLeavesOutMovesPastTheEnds() throws {
        var (library, palette, g) = try sampleLibrary()
        let h = try library.addGroup(name: "H", to: palette, at: t0)
        let i = try library.addGroup(name: "I", to: palette, at: t0)
        let p = try #require(library.palette(palette))
        #expect(GroupMenuItem.items(for: g, in: p) == [.rename, .moveRight, .delete])
        #expect(GroupMenuItem.items(for: h, in: p) == [.rename, .moveLeft, .moveRight, .delete])
        #expect(GroupMenuItem.items(for: i, in: p) == [.rename, .moveLeft, .delete])
    }

    @Test func groupMenuIsEmptyForALockedPaletteOrMissingGroup() throws {
        var (library, palette, g) = try sampleLibrary()
        let unlocked = try #require(library.palette(palette))
        #expect(GroupMenuItem.items(for: UUID(), in: unlocked).isEmpty)
        try library.setLocked(true, palette: palette, at: t0)
        let locked = try #require(library.palette(palette))
        #expect(GroupMenuItem.items(for: g, in: locked).isEmpty)
    }

    @Test func swatchMenu() throws {
        var (library, palette, g) = try sampleLibrary()
        let p = try #require(library.palette(palette))
        #expect(SwatchMenuItem.items(in: nil, of: p) == [.copyAs, .edit, .rename, .delete])
        #expect(SwatchMenuItem.items(in: g, of: p) == [.copyAs, .edit, .rename, .delete, .group])
        // Color History
        #expect(SwatchMenuItem.items(in: nil, of: nil) == [.copyAs])
        try library.setLocked(true, palette: palette, at: t0)
        let locked = try #require(library.palette(palette))
        #expect(SwatchMenuItem.items(in: g, of: locked) == [.copyAs])
    }

    @Test func deletionPredicates() throws {
        let (library, palette, _) = try sampleLibrary()
        let p = try #require(library.palette(palette))
        #expect(p.deletionNeedsConfirmation)
        #expect(!Palette(name: "Empty", at: t0).deletionNeedsConfirmation)
        let onlyEmptyGroup = Palette(name: "E", createdAt: t0, groups: [SwatchGroup(name: "G")])
        #expect(!onlyEmptyGroup.deletionNeedsConfirmation)

        #expect(p.groups[0].deletionNeedsChoice)
        #expect(!SwatchGroup(name: "Empty").deletionNeedsChoice)
    }
}

@Suite("Palette icon input")
struct PaletteIconInputTests {
    @Test func acceptsOneEmojiGrapheme() {
        #expect(PaletteIcon.emoji(from: "🎨") == .emoji("🎨"))
        #expect(PaletteIcon.emoji(from: " 🎨 \n") == .emoji("🎨"))
        #expect(PaletteIcon.emoji(from: "👍🏽") == .emoji("👍🏽"))
        #expect(PaletteIcon.emoji(from: "🇨🇦") == .emoji("🇨🇦"))
        #expect(PaletteIcon.emoji(from: "👩‍🎨") == .emoji("👩‍🎨"))
        #expect(PaletteIcon.emoji(from: "❤️") == .emoji("❤️"))
    }

    @Test func refusesEverythingElse() {
        for input in ["", "  ", "a", "7", "#", "*", "🎨🎨", "🎨a", "ab", "©"] {
            #expect(PaletteIcon.emoji(from: input) == nil, "\(input)")
        }
    }

    @Test func curatedSymbolsAreUniqueAndSearchable() {
        let all = PaletteIcon.curatedSymbols
        #expect(all.count >= 40)
        #expect(Set(all).count == all.count)
        #expect(all.contains("paintpalette"))
        #expect(PaletteIcon.symbols(matching: "") == all)
        #expect(PaletteIcon.symbols(matching: "  ") == all)
        let hearts = PaletteIcon.symbols(matching: "HEART")
        #expect(!hearts.isEmpty && hearts.allSatisfy { $0.contains("heart") })
        #expect(PaletteIcon.symbols(matching: "zzzz").isEmpty)
    }
}
