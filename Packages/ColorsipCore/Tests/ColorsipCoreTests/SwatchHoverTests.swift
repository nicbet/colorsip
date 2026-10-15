import Foundation
import Testing
@testable import ColorsipCore

private let date = Date(timeIntervalSince1970: 1_700_000_000)
private let red = Swatch(color: CSipColor(.srgb, 1, 0, 0), name: "Red", createdAt: date)

@Suite("Swatch hover label")
struct SwatchHoverLabelTests {
    @Test func showsTheNameAndTheValueOnOneLine() {
        let label = SwatchHoverLabel(swatch: red, format: .cssHex)
        #expect(label.text == "Red (\(OutputFormat.cssHex.string(for: red.color)))")
    }

    @Test func valueFollowsTheFormat() {
        let label = SwatchHoverLabel(swatch: red, format: .cssRGB)
        #expect(label.text == "Red (\(OutputFormat.cssRGB.string(for: red.color)))")
    }

    @Test func withoutANameShowsOnlyTheValue() {
        let label = SwatchHoverLabel(swatch: Swatch(color: red.color, name: "", createdAt: date), format: .cssHex)
        #expect(label.text == OutputFormat.cssHex.string(for: red.color))
    }

    @Test func readsCopiedAfterACopy() {
        let label = SwatchHoverLabel(swatch: red, format: .cssHex, copied: true)
        #expect(label.text == "Copied")
    }
}

@Suite("Swatch hover tracker")
struct SwatchHoverTrackerTests {
    private let a = UUID(), b = UUID()

    @Test func startsWithNothingHovered() {
        #expect(SwatchHoverTracker().hovered == nil)
    }

    @Test func enterAndExit() {
        var tracker = SwatchHoverTracker()
        tracker.enter(a)
        #expect(tracker.hovered == a)
        tracker.exit(a)
        #expect(tracker.hovered == nil)
    }

    @Test func moveInTheUsualOrder() {
        var tracker = SwatchHoverTracker()
        tracker.enter(a)
        tracker.exit(a)
        tracker.enter(b)
        #expect(tracker.hovered == b)
    }

    @Test func lateExitOfThePreviousSwatchIsIgnored() {
        var tracker = SwatchHoverTracker()
        tracker.enter(a)
        tracker.enter(b)
        tracker.exit(a)
        #expect(tracker.hovered == b)
    }

    @Test func clearHidesTheLabel() {
        var tracker = SwatchHoverTracker()
        tracker.enter(a)
        tracker.clear()
        #expect(tracker.hovered == nil)
    }
}

/// Screen coordinates are AppKit's: y grows upward.
@Suite("Hover label placement")
struct HoverLabelPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 100, height: 30)

    @Test func centeredAboveTheSwatch() {
        let anchor = CGRect(x: 400, y: 500, width: 20, height: 20)
        let frame = HoverLabelPlacement.frame(labelSize: size, anchor: anchor, visibleFrame: screen, gap: 4)
        #expect(frame == CGRect(x: 360, y: 524, width: 100, height: 30))
    }

    @Test func flipsBelowWhenThereIsNoRoomAbove() {
        let anchor = CGRect(x: 400, y: 770, width: 20, height: 20)
        let frame = HoverLabelPlacement.frame(labelSize: size, anchor: anchor, visibleFrame: screen, gap: 4)
        #expect(frame == CGRect(x: 360, y: 736, width: 100, height: 30))
    }

    @Test func clampedToTheLeftEdge() {
        let anchor = CGRect(x: 5, y: 500, width: 20, height: 20)
        let frame = HoverLabelPlacement.frame(labelSize: size, anchor: anchor, visibleFrame: screen, gap: 4)
        #expect(frame.minX == 0)
    }

    @Test func clampedToTheRightEdge() {
        let anchor = CGRect(x: 980, y: 500, width: 20, height: 20)
        let frame = HoverLabelPlacement.frame(labelSize: size, anchor: anchor, visibleFrame: screen, gap: 4)
        #expect(frame.maxX == 1000)
    }

    @Test func respectsAVisibleFrameThatDoesNotStartAtZero() {
        let visible = CGRect(x: 1000, y: 0, width: 800, height: 600)
        let anchor = CGRect(x: 1002, y: 300, width: 20, height: 20)
        let frame = HoverLabelPlacement.frame(labelSize: size, anchor: anchor, visibleFrame: visible, gap: 4)
        #expect(frame.minX == 1000)
    }
}
