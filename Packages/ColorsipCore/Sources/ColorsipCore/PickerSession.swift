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

/// The loupe label: the value in the active format, the friendly name and the profile's badge.
public struct PickerLabel: Equatable, Sendable {
    public var value: String
    public var name: String
    /// The profile the value was converted to (`spec.md` §6).
    public var profile: TargetProfile
    /// Whether the next click keeps the picker open: multi mode, or Shift held.
    public var isMulti: Bool

    public init(value: String, name: String, profile: TargetProfile, isMulti: Bool = false) {
        self.value = value
        self.name = name
        self.profile = profile
        self.isMulti = isMulti
    }
}

public enum ArrowDirection: Sendable {
    case left, right, up, down
}

/// What the picker does with picks (`spec.md` §4.4).
public enum PickerMode: Sendable {
    /// The first pick closes the picker.
    case single
    /// Every click picks; Esc, or Return without moving, finishes.
    case multi

    /// The modes the Option menu offers, top to bottom. Contrast joins them in V2.
    public static let menu: [PickerMode] = [.single, .multi]
}

/// What the picker should do after an input.
public enum PickerStep: Equatable, Sendable {
    /// Route the color as a pick, then close the picker if `close`. `paste`: paste it into the app
    /// that was active before the picker opened (`spec.md` §4.5).
    case pick(CSipColor, close: Bool, paste: Bool = false)
    case close
    case none
}

/// The Option mode menu (`spec.md` §4.3), in global coordinates (y up): fixed-size items beside the
/// loupe, on the right unless that leaves the display, vertically centered on it and kept on the
/// display.
public struct PickerModeMenu: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let mode: PickerMode
        public let frame: CGRect
    }

    static let itemSize = CGSize(width: 120, height: 24)
    static let padding = 4.0
    static let gap = 12.0

    public let frame: CGRect
    /// Top to bottom, in ``PickerMode/menu`` order.
    public let items: [Item]

    public init(loupe: CGRect, bounds: CGRect) {
        let size = CGSize(
            width: Self.itemSize.width + Self.padding * 2,
            height: Self.itemSize.height * Double(PickerMode.menu.count) + Self.padding * 2)
        var x = loupe.maxX + Self.gap
        if x + size.width > bounds.maxX { x = loupe.minX - Self.gap - size.width }
        let y = min(max(loupe.midY - size.height / 2, bounds.minY), bounds.maxY - size.height)
        frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        let top = frame.maxY - Self.padding
        items = PickerMode.menu.enumerated().map { i, mode in
            Item(mode: mode, frame: CGRect(
                origin: CGPoint(x: x + Self.padding, y: top - Self.itemSize.height * Double(i + 1)),
                size: Self.itemSize))
        }
    }

    /// The mode of the item at `point`, if any.
    public func mode(at point: CGPoint) -> PickerMode? {
        items.first { $0.frame.contains(point) }?.mode
    }
}

/// The state of one open picker (`spec.md` §4.2–4.4, §6): where the pointer is, which pixels the
/// loupe shows, the loupe size, the mode and the target profile. The overlay renders it; the screen
/// sampler fills in `samples`. Input methods return the ``PickerStep`` the caller carries out.
@MainActor
@Observable
public final class PickerSession {
    public let displays: [PickerDisplay]
    /// Other apps' windows, front to back, for Smart Profiles.
    public let windows: [PickerWindow]
    public let profiles: SmartProfiles
    public private(set) var point: CGPoint
    public private(set) var display: PickerDisplay
    /// A session copy of the loupe size. The caller saves it when the picker closes.
    public private(set) var loupe: LoupeSettings
    /// The grid's colors, matching `grid.cells`; empty until the display's first sample.
    public private(set) var samples: [PixelSample?] = []
    /// The center pixel as sampled, in Display P3, or `nil` until the display's first sample.
    private var sampledCenter: CSipColor?
    /// Every session starts in single mode.
    public private(set) var mode = PickerMode.single
    /// Where the visible cursor is while the mode menu is open (Option held), or `nil` when closed.
    /// The loupe stays frozen at `point` meanwhile.
    public private(set) var cursor: CGPoint?
    private var isModeMenuOpen = false
    private var isShiftHeld = false
    /// Whether the loupe moved since the last pick; true before the first.
    private var movedSincePick = true
    /// An Option still held from the shortcut (Hyper+P) doesn't open the menu until it is released.
    private var optionArmed: Bool

    @ObservationIgnored private var scrollSteps = LoupeScroll()

    /// `optionHeld`: whether Option is down as the picker opens.
    public init(
        displays: [PickerDisplay], loupe: LoupeSettings, point: CGPoint, windows: [PickerWindow] = [],
        profiles: SmartProfiles = SmartProfiles(), optionHeld: Bool = false
    ) {
        precondition(!displays.isEmpty, "The picker needs a display")
        self.displays = displays
        self.windows = windows
        self.profiles = profiles
        self.loupe = loupe
        self.point = point
        optionArmed = !optionHeld
        display = PickerGeometry.display(at: point, in: displays) ?? displays[0]
    }

    /// The profile of the app whose window is under the pointer, or the fallback.
    public var profile: TargetProfile {
        profiles.profile(forBundleID: PickerGeometry.window(at: point, in: windows)?.bundleID)
    }

    /// The center pixel's color converted to ``profile``, unclamped (`spec.md` §5.1), or `nil`
    /// until the display's first sample.
    public var centerColor: CSipColor? {
        sampledCenter?.converted(to: profile.colorSpace)
    }

    public var pixel: PixelPoint { PickerGeometry.pixel(at: point, on: display) }

    public var grid: PixelGrid {
        PixelGrid(center: pixel, size: loupe.gridSize, pixelWidth: display.pixelWidth, pixelHeight: display.pixelHeight)
    }

    /// The loupe's circle, in global coordinates.
    public var loupeFrame: CGRect {
        let d = Double(loupe.diameter)
        return CGRect(x: point.x - d / 2, y: point.y - d / 2, width: d, height: d)
    }

    /// The Option menu, while it is open.
    public var modeMenu: PickerModeMenu? {
        isModeMenuOpen ? PickerModeMenu(loupe: loupeFrame, bounds: display.frame) : nil
    }

    /// The menu item under the cursor.
    public var hoveredMode: PickerMode? {
        cursor.flatMap { modeMenu?.mode(at: $0) }
    }

    /// Follows the pointer. In a gap between displays, the loupe stays where it was. While the mode
    /// menu is open, only the cursor moves.
    public func pointerMoved(to point: CGPoint) {
        if isModeMenuOpen {
            cursor = point
            return
        }
        guard let display = PickerGeometry.display(at: point, in: displays) else { return }
        if display != self.display {
            self.display = display
            samples = []
            sampledCenter = nil
        }
        if point != self.point { movedSincePick = true }
        self.point = point
    }

    /// Option down opens the mode menu and freezes the loupe; Option up closes it and returns the
    /// frozen point to move the pointer back to (`nil` if the menu wasn't open).
    @discardableResult
    public func optionChanged(isDown: Bool) -> CGPoint? {
        if !isDown { optionArmed = true }
        guard optionArmed, isDown != isModeMenuOpen else { return nil }
        isModeMenuOpen = isDown
        cursor = isDown ? point : nil
        return isDown ? nil : point
    }

    /// Shift makes the next click keep the picker open, which the label shows.
    public func shiftChanged(isDown: Bool) {
        isShiftHeld = isDown
    }

    public func setMode(_ mode: PickerMode) {
        self.mode = mode
    }

    /// Moves 1 physical pixel, or 10 with Shift, and returns the new point to move the pointer to.
    /// Does nothing while the mode menu is open.
    @discardableResult
    public func arrow(_ direction: ArrowDirection, shift: Bool) -> CGPoint {
        guard !isModeMenuOpen else { return point }
        movedSincePick = true
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

    /// The colors read for the current `grid` and its center pixel, in the capture's Display P3.
    public func sampled(_ samples: [PixelSample?], center: CSipColor?) {
        self.samples = samples
        sampledCenter = center
    }

    public func label(format: OutputFormat) -> PickerLabel? {
        centerColor.map {
            PickerLabel(
                value: $0.formatted(as: format), name: $0.friendlyName, profile: profile,
                isMulti: mode == .multi || isShiftHeld)
        }
    }

    // MARK: Picking (`spec.md` §4.3–4.4)

    /// A click at `location`. It picks; it closes in single mode unless Shift is down. With Command,
    /// in either mode and even with Shift, it picks, closes and pastes. While the mode menu is open,
    /// a click on an item selects that mode instead, and other clicks do nothing.
    public func click(at location: CGPoint, shift: Bool, command: Bool = false) -> PickerStep {
        if let menu = modeMenu {
            if let mode = menu.mode(at: location) { self.mode = mode }
            return .none
        }
        if command { return pick(close: true, paste: true) }
        return pick(close: mode == .single && !shift)
    }

    /// Return or Space. It picks and closes in single mode. In multi mode it picks if the loupe
    /// moved since the last pick, and finishes otherwise.
    public func confirm() -> PickerStep {
        guard !isModeMenuOpen else { return .none }
        switch mode {
        case .single: return pick(close: true)
        case .multi: return movedSincePick ? pick(close: false) : .close
        }
    }

    /// Esc closes the picker. Picks already made are kept: they were routed as they happened.
    public func cancel() -> PickerStep {
        .close
    }

    /// Picks the center color, or does nothing before the first sample.
    private func pick(close: Bool, paste: Bool = false) -> PickerStep {
        guard let centerColor else { return .none }
        movedSincePick = false
        return .pick(centerColor, close: close, paste: paste)
    }
}
