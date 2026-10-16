import CoreGraphics
import Testing
@testable import ColorsipCore

@Suite("Loupe scroll")
struct LoupeScrollTests {
    @Test func wheelNotchIsOneStepEach() {
        var scroll = LoupeScroll()
        #expect(scroll.steps(deltaY: 1, isPrecise: false, isInverted: false) == 1)
        #expect(scroll.steps(deltaY: 4.5, isPrecise: false, isInverted: false) == 1)
        #expect(scroll.steps(deltaY: -0.1, isPrecise: false, isInverted: false) == -1)
        #expect(scroll.steps(deltaY: 0, isPrecise: false, isInverted: false) == 0)
    }

    @Test func upIsPositiveWithNaturalScrolling() {
        var scroll = LoupeScroll()
        // Natural scrolling reports a swipe up as a negative delta.
        #expect(scroll.steps(deltaY: -1, isPrecise: false, isInverted: true) == 1)
        #expect(scroll.steps(deltaY: 1, isPrecise: false, isInverted: true) == -1)
    }

    @Test func trackpadDeltasAccumulate() {
        var scroll = LoupeScroll()
        #expect(scroll.steps(deltaY: 8, isPrecise: true, isInverted: false) == 0)
        #expect(scroll.steps(deltaY: 8, isPrecise: true, isInverted: false) == 0)
        #expect(scroll.steps(deltaY: 8, isPrecise: true, isInverted: false) == 1)  // 24: 4 left over
        #expect(scroll.steps(deltaY: 40, isPrecise: true, isInverted: false) == 2)  // 44: 4 left over
        #expect(scroll.steps(deltaY: 16, isPrecise: true, isInverted: false) == 1)
    }

    @Test func changingDirectionResetsTheAccumulator() {
        var scroll = LoupeScroll()
        #expect(scroll.steps(deltaY: 15, isPrecise: true, isInverted: false) == 0)
        #expect(scroll.steps(deltaY: -15, isPrecise: true, isInverted: false) == 0)
        #expect(scroll.steps(deltaY: -5, isPrecise: true, isInverted: false) == -1)
    }

    @Test func stepsChangeDiameterOrGridSize() {
        var loupe = LoupeSettings()
        LoupeScroll.apply(2, option: false, to: &loupe)
        #expect(loupe == LoupeSettings(diameter: 240, gridSize: 11))
        LoupeScroll.apply(-1, option: true, to: &loupe)
        #expect(loupe == LoupeSettings(diameter: 240, gridSize: 9))
        LoupeScroll.apply(100, option: false, to: &loupe)
        LoupeScroll.apply(100, option: true, to: &loupe)
        #expect(loupe == LoupeSettings(diameter: 400, gridSize: 31))
        LoupeScroll.apply(-100, option: false, to: &loupe)
        LoupeScroll.apply(-100, option: true, to: &loupe)
        #expect(loupe == LoupeSettings(diameter: 120, gridSize: 5))
    }
}

@Suite("Loupe layout")
struct LoupeLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let label = CGSize(width: 180, height: 40)

    @Test func loupeIsCenteredWithTheLabelBelow() {
        let layout = LoupeLayout(pointer: CGPoint(x: 500, y: 400), diameter: 200, labelSize: label, bounds: bounds)
        #expect(layout.loupe == CGRect(x: 400, y: 300, width: 200, height: 200))
        #expect(layout.label == CGRect(x: 410, y: 252, width: 180, height: 40))
    }

    @Test func labelGoesAboveNearTheBottom() {
        let layout = LoupeLayout(pointer: CGPoint(x: 500, y: 120), diameter: 200, labelSize: label, bounds: bounds)
        #expect(layout.loupe == CGRect(x: 400, y: 20, width: 200, height: 200))
        #expect(layout.label == CGRect(x: 410, y: 228, width: 180, height: 40))
    }

    @Test func labelStaysInsideHorizontally() {
        let left = LoupeLayout(pointer: CGPoint(x: 10, y: 400), diameter: 200, labelSize: label, bounds: bounds)
        #expect(left.loupe.minX == -90)
        #expect(left.label.minX == 0)
        let right = LoupeLayout(pointer: CGPoint(x: 995, y: 400), diameter: 200, labelSize: label, bounds: bounds)
        #expect(right.label.maxX == 1000)
    }

    @Test func labelStaysInsideWhenNeitherSideFits() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let layout = LoupeLayout(pointer: CGPoint(x: 200, y: 150), diameter: 280, labelSize: label, bounds: small)
        #expect(small.contains(layout.label))
    }
}

@MainActor
@Suite("Picker session")
struct PickerSessionTests {
    private func session(at point: CGPoint = CGPoint(x: 10.6, y: 980.9)) -> PickerSession {
        PickerSession(displays: [builtIn, external], loupe: LoupeSettings(), point: point, profiles: .noConversion)
    }

    private let red = CSipColor(.displayP3, 1, 0, 0)

    @Test func startsOnTheDisplayUnderThePointer() {
        let session = session()
        #expect(session.display == builtIn)
        #expect(session.pixel == PixelPoint(x: 21, y: 2))
        #expect(session.grid == PixelGrid(center: PixelPoint(x: 21, y: 2), size: 11, pixelWidth: 3024, pixelHeight: 1964))
        #expect(session.centerColor == nil)
        #expect(session.label() == nil)
    }

    @Test func startingBetweenDisplaysUsesTheFirst() {
        let session = session(at: CGPoint(x: 100, y: -50))
        #expect(session.display == builtIn)
    }

    @Test func pointerMovesAcrossDisplays() {
        let session = session()
        session.sampled([PixelSample(red: 1, green: 0, blue: 0, alpha: 1)], center: red)
        session.pointerMoved(to: CGPoint(x: 1612.7, y: 971.8))
        #expect(session.display == external)
        #expect(session.pixel == PixelPoint(x: 100, y: 10))
        #expect(session.grid.pixelWidth == 1920)
        // The old display's sample doesn't belong to the new one.
        #expect(session.centerColor == nil)
        #expect(session.samples.isEmpty)
    }

    @Test func pointerBetweenDisplaysKeepsTheLastPixel() {
        let session = session()
        session.sampled([], center: red)
        session.pointerMoved(to: CGPoint(x: 100, y: -50))
        #expect(session.display == builtIn)
        #expect(session.pixel == PixelPoint(x: 21, y: 2))
        #expect(session.point == CGPoint(x: 10.6, y: 980.9))
        #expect(session.centerColor == red)
    }

    @Test func arrowKeysMoveOneOrTenPixels() {
        let session = session()
        let warp = session.arrow(.right, shift: false)
        #expect(session.pixel == PixelPoint(x: 22, y: 2))
        #expect(warp == session.point)
        #expect(warp == CGPoint(x: 11.25, y: 980.75))
        session.arrow(.down, shift: true)
        #expect(session.pixel == PixelPoint(x: 22, y: 12))
        session.arrow(.left, shift: false)
        session.arrow(.up, shift: false)
        #expect(session.pixel == PixelPoint(x: 21, y: 11))
    }

    @Test func scrollChangesTheLoupeAndGrid() {
        let session = session()
        session.scroll(deltaY: 1, isPrecise: false, isInverted: false, option: false)
        #expect(session.loupe.diameter == 220)
        session.scroll(deltaY: 1, isPrecise: false, isInverted: false, option: true)
        #expect(session.loupe.gridSize == 13)
        #expect(session.grid.size == 13)
    }

    @Test func labelShowsTheValueInTheSessionsFormatAndTheName() {
        let session = session()
        session.sampled([], center: CSipColor(.srgb, 0, 0, 0))
        #expect(session.format == .cssHex)
        #expect(session.label() == PickerLabel(value: "#000000", name: "Black", profile: .displayP3))
        let rgb = PickerSession(
            displays: [builtIn], loupe: LoupeSettings(), point: CGPoint(x: 10.6, y: 980.9), profiles: .noConversion,
            format: .cssRGB)
        rgb.sampled([], center: CSipColor(.srgb, 0, 0, 0))
        #expect(rgb.label()?.value == "rgb(0 0 0)")
    }
}

@MainActor
@Suite("Picking")
struct PickingTests {
    private let start = CGPoint(x: 10.6, y: 980.9)
    private let red = CSipColor(.displayP3, 1, 0, 0)
    private let green = CSipColor(.displayP3, 0, 1, 0)

    private func session(sampled: Bool = true) -> PickerSession {
        let session = PickerSession(displays: [builtIn, external], loupe: LoupeSettings(), point: start, profiles: .noConversion)
        if sampled { session.sampled([], center: red) }
        return session
    }

    @Test func clickReturnAndSpacePickAndClose() {
        #expect(session().click(at: start, shift: false) == .pick(red, close: true))
        #expect(session().confirm() == .pick(red, close: true))
    }

    @Test func returnAlwaysPicksAndCloses() {
        let session = session()
        #expect(session.confirm() == .pick(red, close: true))
        #expect(session.confirm() == .pick(red, close: true))
        session.pointerMoved(to: CGPoint(x: 20, y: 970))
        session.sampled([], center: green)
        #expect(session.confirm() == .pick(green, close: true))
    }

    @Test func shiftClickPicksAndStays() {
        let session = session()
        #expect(session.click(at: start, shift: true) == .pick(red, close: false))
        #expect(session.click(at: start, shift: true) == .pick(red, close: false))
    }

    @Test func commandClickPicksClosesAndPastesEvenWithShift() {
        #expect(session().click(at: start, shift: false, command: true) == .pick(red, close: true, paste: true))
        #expect(session().click(at: start, shift: true, command: true) == .pick(red, close: true, paste: true))
    }

    @Test func onlyCommandClickPastes() {
        #expect(session().click(at: start, shift: false) == .pick(red, close: true, paste: false))
        #expect(session().confirm() == .pick(red, close: true, paste: false))
        #expect(session(sampled: false).click(at: start, shift: false, command: true) == PickerStep.none)
    }

    @Test func escClosesEvenWithoutASample() {
        #expect(session(sampled: false).cancel() == .close)
        let session = session()
        _ = session.click(at: start, shift: true)
        #expect(session.cancel() == .close)
    }

    @Test func pickingNeedsASample() {
        let session = session(sampled: false)
        #expect(session.click(at: start, shift: false) == PickerStep.none)
        #expect(session.confirm() == PickerStep.none)
        session.sampled([], center: red)
        #expect(session.click(at: start, shift: false) == .pick(red, close: true))
    }

    @Test func labelShowsMultiWhileShiftIsHeld() {
        let session = session()
        #expect(session.label()?.hints == [])
        session.shiftChanged(isDown: true)
        #expect(session.label()?.hints == [.multi])
        session.shiftChanged(isDown: false)
        #expect(session.label()?.hints == [])
    }

    @Test func labelShowsSendWhileCommandIsHeld() {
        let session = session()
        session.commandChanged(isDown: true)
        #expect(session.label()?.hints == [.send])
        session.commandChanged(isDown: false)
        #expect(session.label()?.hints == [])
    }

    @Test func labelShowsMultiBeforeSend() {
        let session = session()
        session.commandChanged(isDown: true)
        session.shiftChanged(isDown: true)
        #expect(session.label()?.hints == [.multi, .send])
    }
}

@MainActor
@Suite("Picker format menu")
struct PickerFormatMenuTests {
    private let start = CGPoint(x: 10.6, y: 980.9)
    private let red = CSipColor(.displayP3, 1, 0, 0)

    private func session() -> PickerSession {
        let session = PickerSession(displays: [builtIn, external], loupe: LoupeSettings(), point: start, profiles: .noConversion)
        session.sampled([], center: red)
        return session
    }

    @Test func layoutIsRightOfTheLoupeAndKeptOnTheDisplay() {
        // Loupe: x -89.4…110.6, y 880.9…1080.9; the display ends at y 982.
        let menu = PickerFormatMenu(loupe: CGRect(x: -89.4, y: 880.9, width: 200, height: 200), bounds: builtIn.frame)
        #expect(menu.frame == CGRect(x: 122.6, y: 710, width: 168, height: 272))
        #expect(menu.items.map(\.format) == OutputFormat.allCases)
        #expect(menu.items[0].frame == CGRect(x: 126.6, y: 954, width: 160, height: 24))
        #expect(menu.items[1].frame == CGRect(x: 126.6, y: 930, width: 160, height: 24))
        #expect(menu.items[10].frame == CGRect(x: 126.6, y: 714, width: 160, height: 24))
    }

    @Test func layoutGoesLeftWhenTheRightDoesNotFit() {
        let menu = PickerFormatMenu(loupe: CGRect(x: 1400, y: 400, width: 200, height: 200), bounds: builtIn.frame)
        #expect(menu.frame == CGRect(x: 1220, y: 364, width: 168, height: 272))
    }

    @Test func hitTestFindsTheItem() {
        let menu = PickerFormatMenu(loupe: CGRect(x: 1400, y: 400, width: 200, height: 200), bounds: builtIn.frame)
        #expect(menu.format(at: CGPoint(x: 1300, y: 620)) == .cssHex)
        #expect(menu.format(at: CGPoint(x: 1300, y: 600)) == .cssHexNoHash)
        #expect(menu.format(at: CGPoint(x: 1300, y: 366)) == nil)  // Padding.
        #expect(menu.format(at: CGPoint(x: 1000, y: 500)) == nil)
    }

    @Test func optionOpensTheMenuBesideTheLoupe() {
        let session = session()
        #expect(session.formatMenu == nil)
        session.optionChanged(isDown: true)
        let menu = try! #require(session.formatMenu)
        #expect(menu == PickerFormatMenu(loupe: session.loupeFrame, bounds: builtIn.frame))
        #expect(session.loupeFrame == CGRect(x: -89.4, y: 880.9, width: 200, height: 200))
    }

    @Test func theLoupeFreezesWhileTheMenuIsOpen() {
        let session = session()
        session.optionChanged(isDown: true)
        let item = session.formatMenu!.items[2].frame
        let cursor = CGPoint(x: item.midX, y: item.midY)
        session.pointerMoved(to: cursor)
        #expect(session.point == start)
        #expect(session.cursor == cursor)
        #expect(session.hoveredFormat == .cssRGB)
        #expect(session.centerColor == red)
    }

    @Test func clickingAnItemSelectsTheFormatWithoutPicking() {
        let session = session()
        session.optionChanged(isDown: true)
        let item = session.formatMenu!.items[2].frame
        #expect(session.click(at: CGPoint(x: item.midX, y: item.midY), shift: false) == PickerStep.none)
        #expect(session.format == .cssRGB)
        #expect(session.label()?.value == red.formatted(as: .cssRGB))
        #expect(session.click(at: CGPoint(x: 700, y: 300), shift: false) == PickerStep.none)
        #expect(session.format == .cssRGB)
        #expect(session.click(at: CGPoint(x: 700, y: 300), shift: false, command: true) == PickerStep.none)
    }

    @Test func keysOtherThanEscDoNothingWhileTheMenuIsOpen() {
        let session = session()
        session.optionChanged(isDown: true)
        #expect(session.confirm() == PickerStep.none)
        session.arrow(.left, shift: true)
        #expect(session.point == start)
        #expect(session.cancel() == .close)
    }

    @Test func releasingOptionClosesTheMenuAndReturnsTheFrozenPoint() {
        let session = session()
        #expect(session.optionChanged(isDown: false) == nil)
        session.optionChanged(isDown: true)
        session.pointerMoved(to: CGPoint(x: 500, y: 500))
        #expect(session.optionChanged(isDown: false) == start)
        #expect(session.formatMenu == nil)
        #expect(session.cursor == nil)
        #expect(session.hoveredFormat == nil)
        // A second Option down while open changes nothing.
        session.optionChanged(isDown: true)
        session.pointerMoved(to: CGPoint(x: 500, y: 500))
        session.optionChanged(isDown: true)
        #expect(session.cursor == CGPoint(x: 500, y: 500))
    }

    @Test func optionHeldFromTheShortcutIsIgnoredUntilReleased() {
        // Hyper+P includes Option: the user may still hold it when the picker opens.
        let session = PickerSession(displays: [builtIn], loupe: LoupeSettings(), point: start, profiles: .noConversion, optionHeld: true)
        session.optionChanged(isDown: true)
        #expect(session.formatMenu == nil)
        #expect(session.optionChanged(isDown: false) == nil)
        session.optionChanged(isDown: true)
        #expect(session.formatMenu != nil)
    }
}

extension SmartProfiles {
    /// Every app, and the fallback, in Display P3: samples come out as they went in.
    static let noConversion = SmartProfiles(rules: [], fallback: .displayP3)
}

@MainActor
@Suite("Picker profiles")
struct PickerProfileTests {
    private let start = CGPoint(x: 100, y: 100)
    /// Outside sRGB.
    private let p3Red = CSipColor(.displayP3, 1, 0, 0)
    private let windows = [
        // Front to back: a Safari window over an Xcode window.
        PickerWindow(frame: CGRect(x: 50, y: 50, width: 100, height: 100), bundleID: "com.apple.Safari"),
        PickerWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400), bundleID: "com.apple.dt.Xcode"),
        PickerWindow(frame: CGRect(x: 500, y: 0, width: 100, height: 100), bundleID: nil),
    ]

    private func session(fallback: TargetProfile = .srgb) -> PickerSession {
        let session = PickerSession(
            displays: [builtIn], loupe: LoupeSettings(), point: start, windows: windows,
            profiles: SmartProfiles(rules: SmartProfiles.defaultRules, fallback: fallback))
        session.sampled([], center: p3Red)
        return session
    }

    @Test func theFrontWindowUnderThePointerChoosesTheProfile() {
        let session = session()
        #expect(session.profile == .srgb)
        #expect(session.centerColor == p3Red.converted(to: .srgb))
        #expect(session.click(at: start, shift: false) == .pick(p3Red.converted(to: .srgb), close: true))
    }

    @Test func conversionToSRGBIsNotClamped() throws {
        let color = try #require(session().centerColor)
        #expect(color.colorSpace == .srgb)
        #expect(color.components[0] > 1)
        #expect(color.components[1] < 0)
    }

    @Test func displayP3KeepsTheSampleAsIs() {
        let session = session()
        session.pointerMoved(to: CGPoint(x: 300, y: 300))
        #expect(session.profile == .displayP3)
        #expect(session.centerColor == p3Red)
    }

    @Test func noWindowOrNoBundleIDUsesTheFallback() {
        let session = session(fallback: .genericRGB)
        session.pointerMoved(to: CGPoint(x: 700, y: 700))
        #expect(session.profile == .genericRGB)
        #expect(session.centerColor?.colorSpace == .genericRGB)
        session.pointerMoved(to: CGPoint(x: 550, y: 50))
        #expect(session.profile == .genericRGB)
    }

    @Test func movingToAnotherWindowReconvertsTheCurrentSample() {
        let session = session()
        session.pointerMoved(to: CGPoint(x: 300, y: 300))
        #expect(session.centerColor?.colorSpace == .displayP3)
        session.pointerMoved(to: start)
        #expect(session.centerColor?.colorSpace == .srgb)
    }

    @Test func labelCarriesTheProfile() {
        let session = session()
        #expect(session.label()?.profile == .srgb)
        session.pointerMoved(to: CGPoint(x: 300, y: 300))
        #expect(session.label()?.profile == .displayP3)
    }

    @Test func withoutWindowsEverythingUsesTheFallback() {
        let session = PickerSession(displays: [builtIn], loupe: LoupeSettings(), point: start)
        session.sampled([], center: p3Red)
        #expect(session.profile == .srgb)
        #expect(session.centerColor == p3Red.converted(to: .srgb))
    }
}
