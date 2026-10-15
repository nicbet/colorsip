import Foundation
import Testing
@testable import ColorsipCore

private let installedAt = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Starter palettes")
struct StarterPalettesTests {
    @Test func tailwindCatalogueHasThePinnedFamiliesAndShades() throws {
        let collection = StarterPaletteCatalog.tailwindCSSV4
        #expect(collection.id == "tailwind-css-v4.1.18")
        #expect(collection.name == "Tailwind CSS v4.1.18")
        #expect(collection.sourceURL.absoluteString == "https://github.com/tailwindlabs/tailwindcss/blob/v4.1.18/packages/tailwindcss/theme.css")
        #expect(collection.palettes.map(\.name) == [
            "Slate", "Gray", "Zinc", "Neutral", "Stone", "Red", "Orange", "Amber", "Yellow",
            "Lime", "Green", "Emerald", "Teal", "Cyan", "Sky", "Blue", "Indigo", "Violet",
            "Purple", "Fuchsia", "Pink", "Rose",
        ])
        #expect(StarterPaletteCatalog.collections.map(\.id) == [collection.id])
        #expect(collection.palettes.allSatisfy { $0.swatches.map(\.name) == [
            "50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950",
        ] })
        #expect(collection.palettes.allSatisfy { starter in
            starter.swatches.allSatisfy { $0.color.colorSpace == .oklch && $0.color.alpha == 1 }
        })
        #expect(Set(collection.palettes.map(\.id)).count == 22)
        #expect(Set(collection.palettes.flatMap { $0.swatches.map(\.id) }).count == 242)

        let red = try #require(collection.palettes.first { $0.name == "Red" })
        expectComponents(try #require(red.swatches.first { $0.name == "500" }).color,
                         .oklch, [0.637, 0.237, 25.331], tolerance: 0)
        let neutral = try #require(collection.palettes.first { $0.name == "Neutral" })
        expectComponents(try #require(neutral.swatches.first { $0.name == "50" }).color,
                         .oklch, [0.985, 0, 0], tolerance: 0)
    }

    @Test func catalogueIDsAreStable() throws {
        let slate = try #require(StarterPaletteCatalog.tailwindCSSV4.palettes.first)
        #expect(slate.id == UUID(uuidString: "2295A400-0000-4000-8000-000000000001"))
        #expect(slate.swatches.first?.id == UUID(uuidString: "2295A401-0000-4000-8000-000000001001"))
    }

    @Test func makesAnOrdinaryUnlockedPaletteAtTheInstallationTime() throws {
        let blue = try #require(StarterPaletteCatalog.tailwindCSSV4.palettes.first { $0.name == "Blue" })
        let palette = blue.makePalette(at: installedAt)
        #expect(palette.id == blue.id)
        #expect(palette.name == "Tailwind Blue")
        #expect(palette.description == "Tailwind CSS v4.1.18 — MIT")
        #expect(palette.isLocked == false)
        #expect(palette.createdAt == installedAt)
        #expect(palette.modifiedAt == installedAt)
        #expect(palette.groups.isEmpty)
        #expect(palette.ungrouped.map(\.id) == blue.swatches.map(\.id))
        #expect(palette.ungrouped.allSatisfy { $0.createdAt == installedAt && $0.modifiedAt == installedAt })
    }

    @Test func installsOneByStableIdentityAndAllowsReaddingAfterDeletion() throws {
        let blue = try #require(StarterPaletteCatalog.tailwindCSSV4.palettes.first { $0.name == "Blue" })
        var library = Library(palettes: [Palette(name: "Tailwind Blue", at: installedAt)])

        #expect(!library.contains(starterPalette: blue))
        let firstInstall = library.install(blue, at: installedAt)
        #expect(firstInstall)
        #expect(library.contains(starterPalette: blue))
        #expect(library.palettes.map(\.name) == ["Tailwind Blue", "Tailwind Blue"])
        let duplicateInstall = library.install(blue, at: installedAt)
        #expect(!duplicateInstall)

        try library.renamePalette(blue.id, to: "Brand Blue", at: installedAt.addingTimeInterval(1))
        #expect(library.contains(starterPalette: blue))
        try library.deletePalette(blue.id)
        #expect(!library.contains(starterPalette: blue))
        let reinstall = library.install(blue, at: installedAt.addingTimeInterval(2))
        #expect(reinstall)
        #expect(library.palette(blue.id)?.name == "Tailwind Blue")
    }

    @Test func installsOnlyMissingPalettesInCatalogueOrder() throws {
        let collection = StarterPaletteCatalog.tailwindCSSV4
        let installed = collection.palettes[5]
        var library = Library(palettes: [installed.makePalette(at: installedAt)])
        let added = library.installMissing(from: collection, at: installedAt.addingTimeInterval(1))

        #expect(added == 21)
        #expect(library.palettes.first?.id == installed.id)
        #expect(Array(library.palettes.dropFirst().map(\.id)) == collection.palettes.filter { $0.id != installed.id }.map(\.id))
        let secondAdded = library.installMissing(from: collection, at: installedAt)
        #expect(secondAdded == 0)
    }
}

@MainActor
@Suite("Starter palette controller")
struct StarterPaletteControllerTests {
    @Test func addAndAddAllPersistAsUndoableChanges() throws {
        let temp = TempLibrary()
        defer { temp.cleanUp() }
        let controller = LibraryController(store: temp.store)
        let collection = StarterPaletteCatalog.tailwindCSSV4
        let first = try #require(collection.palettes.first)

        #expect(controller.addStarterPalette(first, at: installedAt))
        #expect(!controller.addStarterPalette(first, at: installedAt))
        #expect(temp.store.load().library.palettes.map(\.id) == [first.id])

        #expect(controller.addMissingStarterPalettes(from: collection, at: installedAt) == 21)
        #expect(controller.library.palettes.count == 22)
        #expect(temp.store.load().library.palettes.count == 22)
        #expect(controller.undoActionName == "Add Tailwind CSS v4.1.18 Starter Palettes")

        controller.undo()
        #expect(controller.library.palettes.map(\.id) == [first.id])
        controller.redo()
        #expect(controller.library.palettes.map(\.id) == collection.palettes.map(\.id))
    }
}
