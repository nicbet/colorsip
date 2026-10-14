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
        PickerSession(displays: [builtIn, external], loupe: LoupeSettings(), point: point)
    }

    private let red = CSipColor(.displayP3, 1, 0, 0)

    @Test func startsOnTheDisplayUnderThePointer() {
        let session = session()
        #expect(session.display == builtIn)
        #expect(session.pixel == PixelPoint(x: 21, y: 2))
        #expect(session.grid == PixelGrid(center: PixelPoint(x: 21, y: 2), size: 11, pixelWidth: 3024, pixelHeight: 1964))
        #expect(session.centerColor == nil)
        #expect(session.label(format: .cssHex) == nil)
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

    @Test func labelShowsTheValueAndName() {
        let session = session()
        session.sampled([], center: CSipColor(.srgb, 0, 0, 0))
        #expect(session.label(format: .cssHex) == PickerLabel(value: "#000000", name: "Black"))
        #expect(session.label(format: .cssRGB)?.value == "rgb(0 0 0)")
    }

    @Test func pickNeedsASample() {
        let session = session()
        #expect(session.finish(.pick) == nil)
        session.sampled([], center: red)
        #expect(session.finish(.pick) == .picked(red))
    }

    @Test func cancelWorksWithoutASample() {
        #expect(session().finish(.cancel) == .cancelled)
    }
}
