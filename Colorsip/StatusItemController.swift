import AppKit
import SwiftUI

/// The menubar icon and its popover (`spec.md` §3.1). The popover can't be detached.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(model: AppModel, actions: PopoverActions) {
        super.init()

        // Every action dismisses the popover first, so a window it opens isn't covered by it.
        let popover = popover
        func closing(_ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
            { popover.performClose(nil); action() }
        }
        let actions = PopoverActions(
            picker: closing(actions.picker),
            repick: closing(actions.repick),
            newPalette: actions.newPalette,
            settings: closing(actions.settings),
            quit: actions.quit
        )

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let content = NSHostingController(rootView: PopoverView(model: model, actions: actions))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eyedropper.halffull", accessibilityDescription: "Colorsip")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        // An agent app has to be active for the transient popover to take key and close on outside
        // clicks.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installBackground()
    }

    /// Puts the popover background behind the popover's frame view, so it fills the arrow too. A
    /// SwiftUI background would leave the arrow in the system material.
    private func installBackground() {
        guard let frameView = popover.contentViewController?.view.window?.contentView?.superview,
              !frameView.subviews.contains(where: { $0 is PopoverBackgroundView })
        else { return }
        let background = PopoverBackgroundView(frame: frameView.bounds)
        background.autoresizingMask = [.width, .height]
        frameView.addSubview(background, positioned: .below, relativeTo: nil)
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        false
    }
}

/// Fills the popover with #E5E7E9 in light mode. Dark mode keeps the system material, so it draws
/// nothing there.
private final class PopoverBackgroundView: NSView {
    private static let color = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .clear
            : NSColor(srgbRed: 0xE5 / 255.0, green: 0xE7 / 255.0, blue: 0xE9 / 255.0, alpha: 1)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Self.color.cgColor
        }
    }
}
