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

/// Draws the loupe and its label (`spec.md` §4.2) when the pointer is on this view's display.
final class LoupeView: NSView {
    struct Content {
        var point: CGPoint
        var diameter: Double
        var gridSize: Int
        var samples: [PixelSample?]
        var colorSpace: CGColorSpace?
        var label: PickerLabel?
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

    private func labelStrings(_ label: PickerLabel) -> (value: NSAttributedString, name: NSAttributedString) {
        (
            NSAttributedString(string: label.value, attributes: [.font: Self.valueFont, .foregroundColor: NSColor.white]),
            NSAttributedString(string: label.name, attributes: [.font: Self.nameFont, .foregroundColor: NSColor(white: 1, alpha: 0.75)])
        )
    }

    private static func size(of label: (value: NSAttributedString, name: NSAttributedString)) -> CGSize {
        let value = label.value.size()
        let name = label.name.size()
        return CGSize(
            width: ceil(max(value.width, name.width)) + labelPadding.width * 2,
            height: ceil(value.height + name.height) + labelPadding.height * 2)
    }

    private func drawLabel(_ label: (value: NSAttributedString, name: NSAttributedString), in rect: CGRect) {
        let capsule = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        capsule.fill()
        let value = label.value.size()
        let name = label.name.size()
        let top = rect.maxY - Self.labelPadding.height
        label.value.draw(at: CGPoint(x: rect.midX - value.width / 2, y: top - value.height))
        label.name.draw(at: CGPoint(x: rect.midX - name.width / 2, y: top - value.height - name.height))
    }
}
