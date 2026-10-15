import AppKit
import ColorsipCore

/// A borderless, transparent panel over one screen while the picker is open.
final class PickerOverlayPanel: NSPanel {
    let displayID: UInt32

    init(screen: NSScreen, displayID: UInt32, content: NSView) {
        self.displayID = displayID
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Set explicitly, a transparent window takes clicks instead of letting them through.
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        content.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView = content
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

/// Draws the loupe, its label (`spec.md` §4.2) and the Option mode menu (§4.3) when the pointer is
/// on this view's display.
final class LoupeView: NSView {
    struct Content {
        var point: CGPoint
        var diameter: Double
        var gridSize: Int
        var samples: [PixelSample?]
        var colorSpace: CGColorSpace?
        var label: PickerLabel?
        /// `nil` unless Option is held.
        var menu: Menu?
    }

    struct Menu {
        /// In global coordinates.
        var layout: PickerModeMenu
        var mode: PickerMode
        var hovered: PickerMode?
    }

    /// `nil` hides the loupe: the pointer is on another display.
    var content: Content? {
        didSet { needsDisplay = true }
    }

    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    private static let nameFont = NSFont.systemFont(ofSize: 11)
    private static let labelPadding = NSSize(width: 10, height: 6)

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let content, let window, let context = NSGraphicsContext.current?.cgContext else { return }
        let local = CGPoint(x: content.point.x - window.frame.minX, y: content.point.y - window.frame.minY)
        let label = content.label.map(labelStrings)
        let labelSize = label.map(Self.size(of:)) ?? .zero
        let layout = LoupeLayout(pointer: local, diameter: content.diameter, labelSize: labelSize, bounds: bounds)
        drawLoupe(in: layout.loupe, content: content, context: context)
        if let label { drawLabel(label, in: layout.label) }
        if let menu = content.menu {
            drawMenu(menu, offset: CGPoint(x: -window.frame.minX, y: -window.frame.minY))
        }
    }

    private func drawLoupe(in rect: CGRect, content: Content, context: CGContext) {
        let circle = NSBezierPath(ovalIn: rect)
        let n = content.gridSize
        let cell = rect.width / Double(n)

        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        NSColor(white: 0.5, alpha: 0.35).setFill()
        rect.fill()
        if let image = gridImage(content) {
            context.interpolationQuality = .none
            context.draw(image, in: rect)
        }
        // Grid lines.
        let lines = NSBezierPath()
        for i in 1..<n {
            let offset = Double(i) * cell
            lines.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            lines.line(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            lines.move(to: CGPoint(x: rect.minX, y: rect.minY + offset))
            lines.line(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
        }
        lines.lineWidth = 0.5
        NSColor(white: 0, alpha: 0.15).setStroke()
        lines.stroke()
        // The center pixel, outlined in black and white so it shows on any color.
        let center = CGRect(x: rect.minX + Double(n / 2) * cell, y: rect.minY + Double(n / 2) * cell, width: cell, height: cell)
        let outer = NSBezierPath(rect: center.insetBy(dx: -1, dy: -1))
        outer.lineWidth = 2
        NSColor.black.setStroke()
        outer.stroke()
        let inner = NSBezierPath(rect: center)
        inner.lineWidth = 1
        NSColor.white.setStroke()
        inner.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // The ring.
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 3
        NSColor.white.setStroke()
        ring.stroke()
        let edge = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        NSColor(white: 0, alpha: 0.4).setStroke()
        edge.stroke()
    }

    /// The samples as an `n × n` float image in the capture's color space, so they look like the
    /// screen.
    private func gridImage(_ content: Content) -> CGImage? {
        let n = content.gridSize
        guard content.samples.count == n * n, let space = content.colorSpace else { return nil }
        var floats = [Float](repeating: 0, count: n * n * 4)
        for (i, sample) in content.samples.enumerated() {
            guard let sample else { continue }  // Off the display: transparent.
            floats[i * 4] = Float(sample.red)
            floats[i * 4 + 1] = Float(sample.green)
            floats[i * 4 + 2] = Float(sample.blue)
            floats[i * 4 + 3] = 1
        }
        guard let provider = CGDataProvider(data: floats.withUnsafeBytes { Data($0) } as CFData) else { return nil }
        let info = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        return CGImage(
            width: n, height: n, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: n * 16, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static let badgeFont = NSFont.systemFont(ofSize: 10, weight: .semibold)

    /// The label's lines, top to bottom: the value with the profile's badge (`spec.md` §6), the
    /// name, and "MULTI" when the next click keeps the picker open.
    private func labelStrings(_ label: PickerLabel) -> [NSAttributedString] {
        let value = NSMutableAttributedString(
            string: label.value, attributes: [.font: Self.valueFont, .foregroundColor: NSColor.white])
        value.append(NSAttributedString(string: "  "))
        value.append(NSAttributedString(string: label.profile.badge, attributes: [
            .font: Self.badgeFont, .foregroundColor: NSColor(white: 1, alpha: 0.6), .kern: 0.5,
            .baselineOffset: 1,
        ]))
        var lines: [NSAttributedString] = [
            value,
            NSAttributedString(string: label.name, attributes: [.font: Self.nameFont, .foregroundColor: NSColor(white: 1, alpha: 0.75)]),
        ]
        if label.isMulti {
            lines.append(NSAttributedString(string: "MULTI", attributes: [
                .font: Self.badgeFont, .foregroundColor: NSColor.controlAccentColor, .kern: 1,
            ]))
        }
        return lines
    }

    private static func size(of lines: [NSAttributedString]) -> CGSize {
        let sizes = lines.map { $0.size() }
        return CGSize(
            width: ceil(sizes.map(\.width).max() ?? 0) + labelPadding.width * 2,
            height: ceil(sizes.map(\.height).reduce(0, +)) + labelPadding.height * 2)
    }

    private func drawLabel(_ lines: [NSAttributedString], in rect: CGRect) {
        let capsule = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        capsule.fill()
        var top = rect.maxY - Self.labelPadding.height
        for line in lines {
            let size = line.size()
            top -= size.height
            line.draw(at: CGPoint(x: rect.midX - size.width / 2, y: top))
        }
    }

    private static let menuFont = NSFont.systemFont(ofSize: 13)

    private static func title(_ mode: PickerMode) -> String {
        switch mode {
        case .single: "Single"
        case .multi: "Multi"
        }
    }

    /// The menu in the label's style: the current mode checked, the hovered item highlighted.
    private func drawMenu(_ menu: Menu, offset: CGPoint) {
        let frame = menu.layout.frame.offsetBy(dx: offset.x, dy: offset.y)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
        for item in menu.layout.items {
            let rect = item.frame.offsetBy(dx: offset.x, dy: offset.y)
            if item.mode == menu.hovered {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.menuFont, .foregroundColor: NSColor.white]
            let check = NSAttributedString(string: item.mode == menu.mode ? "✓" : "", attributes: attributes)
            let title = NSAttributedString(string: Self.title(item.mode), attributes: attributes)
            let y = rect.midY - title.size().height / 2
            check.draw(at: CGPoint(x: rect.minX + 8, y: y))
            title.draw(at: CGPoint(x: rect.minX + 26, y: y))
        }
    }
}
