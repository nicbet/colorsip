import CoreGraphics
import Observation

/// Turns scroll events into loupe steps (`spec.md` §4.2). Up, by wheel or by a two-finger swipe,
/// is a positive step with natural and classic scrolling alike.
public struct LoupeScroll: Sendable {
    /// Trackpad travel, in points, per step.
    static let pointsPerStep = 20.0

    private var accumulated = 0.0

    public init() {}

    /// The steps for one scroll event. A wheel notch (`isPrecise == false`) is one step; trackpad
    /// deltas accumulate, and changing direction starts over.
    public mutating func steps(deltaY: Double, isPrecise: Bool, isInverted: Bool) -> Int {
        let up = isInverted ? -deltaY : deltaY
        guard isPrecise else {
            accumulated = 0
            return up > 0 ? 1 : up < 0 ? -1 : 0
        }
        if up * accumulated < 0 { accumulated = 0 }
        accumulated += up
        let steps = Int(accumulated / Self.pointsPerStep)
        accumulated -= Double(steps) * Self.pointsPerStep
        return steps
    }

    /// Changes the diameter by 20 pt per step, or with Option the grid size by 2.
    public static func apply(_ steps: Int, option: Bool, to loupe: inout LoupeSettings) {
        if option {
            loupe.gridSize += steps * 2
        } else {
            loupe.diameter += steps * LoupeSettings.diameterStep
        }
    }
}

/// Where the loupe and its label go, in the coordinates of `bounds` (y up).
public struct LoupeLayout: Equatable, Sendable {
    static let labelGap = 8.0

    public let loupe: CGRect
    public let label: CGRect

    /// The loupe is centered on the pointer, even if the screen edge clips it. The label sits under
    /// it, or above it when it doesn't fit, and is kept inside `bounds`.
    public init(pointer: CGPoint, diameter: Double, labelSize: CGSize, bounds: CGRect) {
        loupe = CGRect(x: pointer.x - diameter / 2, y: pointer.y - diameter / 2, width: diameter, height: diameter)
        let x = min(max(loupe.midX - labelSize.width / 2, bounds.minX), bounds.maxX - labelSize.width)
        var y = loupe.minY - Self.labelGap - labelSize.height
        if y < bounds.minY {
            let above = loupe.maxY + Self.labelGap
            y = above + labelSize.height <= bounds.maxY ? above : bounds.minY
        }
        label = CGRect(origin: CGPoint(x: x, y: y), size: labelSize)
    }
}

/// The loupe label: the value in the active format and the friendly name.
public struct PickerLabel: Equatable, Sendable {
    public var value: String
    public var name: String

    public init(value: String, name: String) {
        self.value = value
        self.name = name
    }
}

public enum ArrowDirection: Sendable {
    case left, right, up, down
}

public enum PickerAction: Sendable {
    case pick, cancel
}

public enum PickerOutcome: Equatable, Sendable {
    case picked(CSipColor)
    case cancelled
}

/// The state of one open picker (`spec.md` §4.2–4.3): where the pointer is, which pixels the loupe
/// shows, and the loupe size. The overlay renders it; the screen sampler fills in `samples`.
@MainActor
@Observable
public final class PickerSession {
    public let displays: [PickerDisplay]
    public private(set) var point: CGPoint
    public private(set) var display: PickerDisplay
    /// A session copy of the loupe size. The caller saves it when the picker closes.
    public private(set) var loupe: LoupeSettings
    /// The grid's colors, matching `grid.cells`; empty until the display's first sample.
    public private(set) var samples: [PixelSample?] = []
    /// The center pixel's color, or `nil` until the display's first sample.
    public private(set) var centerColor: CSipColor?

    @ObservationIgnored private var scrollSteps = LoupeScroll()

    public init(displays: [PickerDisplay], loupe: LoupeSettings, point: CGPoint) {
        precondition(!displays.isEmpty, "The picker needs a display")
        self.displays = displays
        self.loupe = loupe
        self.point = point
        display = PickerGeometry.display(at: point, in: displays) ?? displays[0]
    }

    public var pixel: PixelPoint { PickerGeometry.pixel(at: point, on: display) }

    public var grid: PixelGrid {
        PixelGrid(center: pixel, size: loupe.gridSize, pixelWidth: display.pixelWidth, pixelHeight: display.pixelHeight)
    }

    /// Follows the pointer. In a gap between displays, the loupe stays where it was.
    public func pointerMoved(to point: CGPoint) {
        guard let display = PickerGeometry.display(at: point, in: displays) else { return }
        if display != self.display {
            self.display = display
            samples = []
            centerColor = nil
        }
        self.point = point
    }

    /// Moves 1 physical pixel, or 10 with Shift, and returns the new point to move the pointer to.
    @discardableResult
    public func arrow(_ direction: ArrowDirection, shift: Bool) -> CGPoint {
        let distance = shift ? 10 : 1
        let (dx, dy) = switch direction {
        case .left: (-distance, 0)
        case .right: (distance, 0)
        case .up: (0, -distance)
        case .down: (0, distance)
        }
        point = PickerGeometry.moved(point, dx: dx, dy: dy, on: display)
        return point
    }

    /// The mouse wheel changes the diameter; with Option, the grid size.
    public func scroll(deltaY: Double, isPrecise: Bool, isInverted: Bool, option: Bool) {
        let steps = scrollSteps.steps(deltaY: deltaY, isPrecise: isPrecise, isInverted: isInverted)
        guard steps != 0 else { return }
        LoupeScroll.apply(steps, option: option, to: &loupe)
    }

    /// The colors read for the current `grid` and its center pixel.
    public func sampled(_ samples: [PixelSample?], center: CSipColor?) {
        self.samples = samples
        centerColor = center
    }

    public func label(format: OutputFormat) -> PickerLabel? {
        centerColor.map { PickerLabel(value: $0.formatted(as: format), name: $0.friendlyName) }
    }

    /// The outcome of picking or cancelling. Picking before the first sample does nothing (`nil`).
    public func finish(_ action: PickerAction) -> PickerOutcome? {
        switch action {
        case .pick: centerColor.map(PickerOutcome.picked)
        case .cancel: .cancelled
        }
    }
}
