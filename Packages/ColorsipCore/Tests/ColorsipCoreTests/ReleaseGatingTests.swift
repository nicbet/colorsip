import Testing
@testable import ColorsipCore

@Suite("Release gating")
struct ReleaseGatingTests {
    @Test func releasesAreOrdered() {
        #expect(Release.mvp < .v2)
        #expect(Release.v2 < .v3)
    }

    @Test func currentReleaseIsMVP() {
        #expect(Release.current == .mvp)
    }

    @Test func mvpToolbarShowsOnlyPickerAndNewPalette() {
        #expect(PopoverItem.toolbar(for: .mvp) == [.picker, .newPalette])
    }

    @Test func v2ToolbarShowsEverythingInSpecOrder() {
        #expect(PopoverItem.toolbar(for: .v2) == [.picker, .contrastChecker, .newPalette, .visionSimulation])
    }

    @Test func mvpBottomBarShowsOnlySettingsAndQuit() {
        #expect(PopoverItem.bottomBar(for: .mvp) == [.settings, .quit])
    }

    @Test func v2BottomBarShowsEverythingInSpecOrder() {
        #expect(PopoverItem.bottomBar(for: .v2) == [.settings, .visionMode, .openMainWindow, .quit])
    }

    @Test func laterReleasesKeepEarlierItems() {
        #expect(PopoverItem.toolbar(for: .v3) == PopoverItem.toolbar(for: .v2))
        #expect(PopoverItem.bottomBar(for: .v3) == PopoverItem.bottomBar(for: .v2))
    }

    @Test func mvpMainWindowShowsOnlySettings() {
        #expect(MainWindowTab.visible(for: .mvp) == [.settings])
    }

    @Test func v2MainWindowAddsLibraryFirst() {
        #expect(MainWindowTab.visible(for: .v2) == [.library, .settings])
    }
}

@Suite("Output format catalogue")
struct OutputFormatCatalogueTests {
    @Test func listsTheFormatsInSpecOrder() {
        #expect(OutputFormat.allCases.map(\.displayName) == [
            "CSS Hex", "CSS Hex (no #)", "CSS RGB", "CSS HSL", "CSS OKLCH", "CSS Display P3",
            "SwiftUI", "NSColor", "UIColor", "Android", "Android (XML)",
        ])
    }

    @Test func defaultIsCSSHex() {
        #expect(OutputFormat.default == .cssHex)
    }
}
