import AppKit
import ColorsipCore

/// The picker (`spec.md` §4.1–4.4): overlays every screen, follows the pointer with the loupe and
/// reports each pick. A thin layer over `PickerSession`.
@MainActor
final class PickerController {
    /// Called for every pick, as it is made; a multi session calls it several times.
    var onPick: @MainActor (CSipColor) -> Void = { _ in }
    /// Set while the color editor's eyedropper picks: it gets the first pick, or `nil` if the
    /// picker closes without one, instead of `onPick`.
    private var repick: (@MainActor (CSipColor?) -> Void)?

    private let model: AppModel
    private var session: PickerSession?
    private var panels: [PickerOverlayPanel] = []
    private var monitor: Any?
    private var screenObserver: (any NSObjectProtocol)?
    private lazy var sampler = ScreenSampler(
        onFrame: { [weak self] in self?.resample() },
        onError: { [weak self] _ in self?.close() })

    init(model: AppModel) {
        self.model = model
    }

    var isOpen: Bool { session != nil }

    /// Opens the picker for the color editor's eyedropper (`spec.md` §5.4): the first pick goes to
    /// `completion` and closes the picker. It isn't routed like other picks.
    func open(repick completion: @escaping @MainActor (CSipColor?) -> Void) {
        guard session == nil else { return completion(nil) }
        repick = completion
        open()
        if session == nil { finishRepick(nil) }
    }

    func open() {
        guard session == nil else { return }
        let screens = NSScreen.screens.compactMap { screen in screen.displayID.map { (screen, $0) } }
        guard !screens.isEmpty else { return }
        let displays = screens.map { screen, id in
            PickerDisplay(id: id, frame: screen.frame, scale: screen.backingScaleFactor)
        }
        session = PickerSession(
            displays: displays, loupe: model.settings.settings.loupe, point: NSEvent.mouseLocation,
            optionHeld: NSEvent.modifierFlags.contains(.option))
        session?.shiftChanged(isDown: NSEvent.modifierFlags.contains(.shift))
        panels = screens.map { screen, id in PickerOverlayPanel(screen: screen, displayID: id, content: LoupeView()) }

        NSApp.activate()
        panels.forEach { $0.orderFrontRegardless() }
        panels.first { $0.displayID == session?.display.id }?.makeKey()
        NSCursor.hide()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel,
                .keyDown, .flagsChanged,
            ]
        ) { [weak self] event in
            guard let self else { return event }
            return handle(event) ? nil : event
        }
        // A display added, removed or rearranged invalidates every frame and panel.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        displayChanged()
    }

    // MARK: Events

    /// Returns whether the event was handled, so it doesn't reach other windows.
    private func handle(_ event: NSEvent) -> Bool {
        guard let session else { return false }
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            moved(to: NSEvent.mouseLocation)
        case .leftMouseDown:
            perform(session.click(at: NSEvent.mouseLocation, shift: event.modifierFlags.contains(.shift)))
        case .flagsChanged:
            session.shiftChanged(isDown: event.modifierFlags.contains(.shift))
            optionChanged(isDown: event.modifierFlags.contains(.option), session: session)
            return false
        case .rightMouseDown:
            break
        case .scrollWheel:
            // Momentum after a trackpad swipe would keep resizing the loupe.
            guard event.momentumPhase.isEmpty else { return true }
            session.scroll(
                deltaY: event.scrollingDeltaY, isPrecise: event.hasPreciseScrollingDeltas,
                isInverted: event.isDirectionInvertedFromDevice, option: event.modifierFlags.contains(.option))
            resample()
        case .keyDown:
            return key(event, session: session)
        default:
            return false
        }
        return true
    }

    private func key(_ event: NSEvent, session: PickerSession) -> Bool {
        let shift = event.modifierFlags.contains(.shift)
        let direction: ArrowDirection
        switch Int(event.keyCode) {
        case 53: perform(session.cancel()); return true  // Esc
        case 36, 76, 49: perform(session.confirm()); return true  // Return, keypad Enter, Space
        case 123: direction = .left
        case 124: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        default: return true  // Swallow other keys while picking.
        }
        guard session.modeMenu == nil else { return true }
        warp(to: session.arrow(direction, shift: shift))
        resample()
        return true
    }

    /// Option opens the mode menu and shows the cursor so it can reach the menu; releasing it puts
    /// the pointer back under the frozen loupe.
    private func optionChanged(isDown: Bool, session: PickerSession) {
        let wasOpen = session.modeMenu != nil
        let frozen = session.optionChanged(isDown: isDown)
        if !wasOpen && session.modeMenu != nil {
            NSCursor.unhide()
        } else if let frozen {
            warp(to: frozen)
            NSCursor.hide()
        }
        resample()
    }

    private func perform(_ step: PickerStep) {
        switch step {
        case .pick(let color, _) where repick != nil:
            finishRepick(color)
            close()
        case .pick(let color, let close):
            onPick(color)
            if close { self.close() } else { resample() }
        case .close:
            close()
        case .none:
            resample()  // A mode chosen in the menu.
        }
    }

    private func moved(to point: CGPoint) {
        guard let session else { return }
        let display = session.display
        session.pointerMoved(to: point)
        if session.display != display {
            displayChanged()
        } else {
            resample()
        }
    }

    /// Moves the real pointer, which `CGWarpMouseCursorPosition` takes in top-left-origin
    /// coordinates.
    private func warp(to point: CGPoint) {
        guard let primary = NSScreen.screens.first else { return }
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primary.frame.maxY - point.y))
        // Without this, the pointer ignores the mouse for a moment after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: Sampling and drawing

    private func displayChanged() {
        guard let session else { return }
        let id = session.display.id
        sampler.capture(id)
        panels.first { $0.displayID == id }?.makeKey()
        resample()
    }

    /// Reads the grid from the latest frame and redraws.
    private func resample() {
        guard let session else { return }
        if let frame = sampler.frame {
            let sample = frame.sample(session.grid)
            session.sampled(sample.samples, center: sample.center)
        }
        let content = LoupeView.Content(
            point: session.point,
            diameter: Double(session.loupe.diameter),
            gridSize: session.loupe.gridSize,
            samples: session.samples,
            colorSpace: sampler.frame?.colorSpace,
            label: session.label(format: model.outputFormat),
            menu: session.modeMenu.map { LoupeView.Menu(layout: $0, mode: session.mode, hovered: session.hoveredMode) })
        for panel in panels {
            (panel.contentView as? LoupeView)?.content = panel.displayID == session.display.id ? content : nil
        }
    }

    // MARK: Closing

    private func finishRepick(_ color: CSipColor?) {
        let completion = repick
        repick = nil
        completion?(color)
    }

    /// Closes the picker. Picks were already reported as they were made; a re-pick that closes
    /// without a pick reports `nil`.
    private func close() {
        defer { finishRepick(nil) }
        guard let session else { return }
        self.session = nil
        sampler.stop()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        // With the mode menu open, the cursor is already showing.
        if session.modeMenu == nil { NSCursor.unhide() }
        // Saved once per session, not on every wheel notch.
        model.settings.update { $0.loupe = session.loupe }
    }
}

extension NSScreen {
    /// The `CGDirectDisplayID`.
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
