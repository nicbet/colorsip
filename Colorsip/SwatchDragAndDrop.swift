import AppKit
import ColorsipCore
import SwiftUI
import UniformTypeIdentifiers

/// Dragging swatches (`spec.md` §7.5). The drag is an AppKit drag session, so other apps get the
/// value as text in the active format plus an `NSColor`.
///
/// - It isn't SwiftUI's `.onDrag`: on macOS that source only allows copy, so a drop proposing move
///   fails, and proposing copy shows a + on every drop.
/// - There is no custom pasteboard type: an undeclared one didn't work in the popover (cs-d6bd2c),
///   and SwiftUI hands a drop from this app an empty item provider anyway. The popover's drop
///   targets read what is dragged from ``AppModel/drag``.
extension View {
    /// Makes `swatch` draggable as `source`. A `DragGesture` notices the drag, then hands it to
    /// AppKit; its minimum distance keeps clicks and right-clicks working.
    func swatchDrag(_ swatch: Swatch, as source: SwatchDragSource, model: AppModel) -> some View {
        gesture(DragGesture(minimumDistance: 4).onChanged { _ in
            // Once the session runs, AppKit owns the mouse and SwiftUI may not see the gesture end,
            // so `model.drag` (cleared when the session ends) keeps this to one session per drag.
            guard model.drag == nil else { return }
            SwatchDragSession.begin(swatch, as: source, model: model)
        })
    }

    /// Makes the view a drop target for dragged swatches. `slot` maps the pointer to a section and a
    /// slot in it; `targeted` reports the slot while a drop here would be accepted, `nil` otherwise.
    func swatchDrop(
        model: AppModel, palette: Palette.ID, slot: @escaping (CGPoint) -> StripSlot,
        targeted: @escaping (StripSlot?) -> Void
    ) -> some View {
        onDrop(of: [.utf8PlainText], delegate: SwatchDropDelegate(model: model, palette: palette, slot: slot, targeted: targeted))
    }
}

/// A strip's drop target, or nothing for Color History (`palette == nil`), which takes no drops.
struct StripDrop: ViewModifier {
    let model: AppModel
    let palette: Palette.ID?
    let slot: (CGPoint) -> StripSlot
    let targeted: (StripSlot?) -> Void

    func body(content: Content) -> some View {
        if let palette {
            content.swatchDrop(model: model, palette: palette, slot: slot, targeted: targeted)
        } else {
            content
        }
    }
}

private struct SwatchDropDelegate: DropDelegate {
    let model: AppModel
    let palette: Palette.ID
    let slot: (CGPoint) -> StripSlot
    let targeted: (StripSlot?) -> Void

    private var option: Bool { NSEvent.modifierFlags.contains(.option) }

    private func operation() -> SwatchDropOperation? {
        guard let drag = model.drag else { return nil }
        return SwatchDrag.operation(for: drag, onto: palette, in: model.library.library, option: option)
    }

    /// Only our own drags: a drag from another app has no ``AppModel/drag``.
    func validateDrop(info: DropInfo) -> Bool {
        model.drag != nil && info.hasItemsConforming(to: [.utf8PlainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let operation = operation()
        targeted(operation == nil ? nil : slot(info.location))
        switch operation {
        case .move: return DropProposal(operation: .move)
        case .copy: return DropProposal(operation: .copy)
        case nil: return DropProposal(operation: .forbidden)
        }
    }

    func dropExited(info: DropInfo) {
        targeted(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted(nil)
        // The dropped item can't be read back: for a drag from this app, SwiftUI hands the target
        // an empty item provider. ``AppModel/drag`` says what was dragged.
        guard operation() != nil else { return false }
        let slot = slot(info.location)
        model.dropDrag(onto: SectionID(palette: palette, group: slot.group), at: slot.index, option: option)
        return true
    }
}

/// The source of a swatch's drag session. It allows move and copy within the app, so drop targets
/// can show which one a drop does, and only copy outside it, so a drop into another app never
/// removes the swatch.
@MainActor
final class SwatchDragSession: NSObject, NSDraggingSource {
    /// The running session's source, kept alive until the session ends.
    private static var current: SwatchDragSession?

    private let model: AppModel

    private init(model: AppModel) {
        self.model = model
    }

    /// Starts dragging `swatch` from the current mouse-dragged event's window (the popover).
    static func begin(_ swatch: Swatch, as source: SwatchDragSource, model: AppModel) {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let view = event.window?.contentView
        else { return }
        let item = NSPasteboardItem()
        item.setString(SwatchDrag.payload(for: swatch.color, format: model.outputFormat), forType: .string)
        // What NSColor itself writes to a pasteboard: a keyed archive under the color type.
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: swatch.color.nsColor, requiringSecureCoding: true) {
            item.setData(data, forType: .color)
        }
        let size = 24.0
        let point = view.convert(event.locationInWindow, from: nil)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(
            NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
            contents: preview(swatch.color.nsColor, size: size))

        let session = SwatchDragSession(model: model)
        current = session
        model.drag = source
        view.beginDraggingSession(with: [draggingItem], event: event, source: session)
    }

    private static func preview(_ color: NSColor, size: Double) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            return true
        }
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : .copy
    }

    /// The drop has happened (`performDrop` already used ``AppModel/drag``), was cancelled, or went
    /// to another app. Either way the drag is over.
    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            model.drag = nil
            Self.current = nil
        }
    }
}

extension CSipColor {
    /// The color for other apps' `NSColor` drop targets.
    var nsColor: NSColor {
        let c = displayP3Components
        return NSColor(displayP3Red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
