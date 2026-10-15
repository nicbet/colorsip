import AppKit
import ColorsipCore
import SwiftUI

/// The label over a hovered swatch. It lives in its own panel because a SwiftUI overlay would be
/// clipped by the strip and the palette list, and a popover animates and reopens as it moves. The
/// panel ignores the mouse, so clicks, drags and right-clicks reach the swatch underneath.
@MainActor
final class SwatchHoverPanel {
    static let shared = SwatchHoverPanel()

    private var tracker = SwatchHoverTracker()
    private var label: SwatchHoverLabel?
    private let host = NSHostingView(rootView: SwatchHoverLabelView(label: nil))
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Menus share the level and open later, so a context menu covers the label.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        return panel
    }()

    private var anchor: CGRect?

    /// Shows `label` for swatch `id` next to `anchor`, the swatch's frame on screen.
    func show(_ id: Swatch.ID, label: SwatchHoverLabel, anchor: CGRect) {
        tracker.enter(id)
        self.anchor = anchor
        place(label, at: anchor)
        panel.orderFrontRegardless()
    }

    /// Changes the text of the label on swatch `id`, for example to Copied, if it's showing.
    func update(_ id: Swatch.ID, label: SwatchHoverLabel) {
        guard tracker.hovered == id, let anchor else { return }
        place(label, at: anchor)
    }

    private func place(_ label: SwatchHoverLabel, at anchor: CGRect) {
        if label != self.label {
            self.label = label
            host.rootView = SwatchHoverLabelView(label: label)
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let frame = HoverLabelPlacement.frame(
            labelSize: host.fittingSize, anchor: anchor, visibleFrame: screen?.visibleFrame ?? anchor, gap: 4)
        panel.setFrame(frame, display: true)
    }

    /// The pointer left swatch `id`. Ignored if it's already over another one.
    func exit(_ id: Swatch.ID) {
        tracker.exit(id)
        if tracker.hovered == nil { orderOut() }
    }

    func hide() {
        tracker.clear()
        orderOut()
    }

    private func orderOut() {
        label = nil
        anchor = nil
        panel.orderOut(nil)
    }
}

private struct SwatchHoverLabelView: View {
    let label: SwatchHoverLabel?

    var body: some View {
        if let label {
            Text(label.text)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .frame(maxWidth: 280)
                .fixedSize()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
