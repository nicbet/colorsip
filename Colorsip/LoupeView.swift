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

/// Draws the loupe, its label (`spec.md` §4.2) and the Option format menu (§4.3) when the pointer is
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
        var layout: PickerFormatMenu
        var format: OutputFormat
        var hovered: OutputFormat?
    }

    /// `nil` hides the loupe: the pointer is on another display.
    var content: Content? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let content, let window, let context = NSGraphicsContext.current?.cgContext else { return }
        let local = CGPoint(x: content.point.x - window.frame.minX, y: content.point.y - window.frame.minY)
        let label = content.label.map(LoupeLabel.init)
        let layout = LoupeLayout(pointer: local, diameter: content.diameter, labelSize: label?.size ?? .zero, bounds: bounds)
        drawLoupe(in: layout.loupe, content: content, context: context)
        label?.draw(in: layout.label, swatch: centerColor(content))
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

    /// The center pixel as a color in the capture's color space, for the label's swatch.
    private func centerColor(_ content: Content) -> CGColor? {
        let n = content.gridSize
        guard content.samples.count == n * n, let space = content.colorSpace,
            let sample = content.samples[n * n / 2]
        else { return nil }
        return CGColor(colorSpace: space, components: [sample.red, sample.green, sample.blue, 1])
    }

    private static let menuFont = NSFont.systemFont(ofSize: 13)

    /// The menu in the dark pill's style: the current format checked, the hovered item highlighted.
    private func drawMenu(_ menu: Menu, offset: CGPoint) {
        let frame = menu.layout.frame.offsetBy(dx: offset.x, dy: offset.y)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
        for item in menu.layout.items {
            let rect = item.frame.offsetBy(dx: offset.x, dy: offset.y)
            if item.format == menu.hovered {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.menuFont, .foregroundColor: NSColor.white]
            let check = NSAttributedString(string: item.format == menu.format ? "✓" : "", attributes: attributes)
            let title = NSAttributedString(string: item.format.displayName, attributes: attributes)
            let y = rect.midY - title.size().height / 2
            check.draw(at: CGPoint(x: rect.minX + 8, y: y))
            title.draw(at: CGPoint(x: rect.minX + 26, y: y))
        }
    }
}

/// The loupe label (`spec.md` §4.2): a white pill with the swatch, "name • value" and the
/// hints, over a small dark pill with the profile. Both are centered in the label's rect.
private struct LoupeLabel {
    private static let primaryHeight = 28.0
    private static let secondaryHeight = 24.0
    private static let pillGap = 6.0
    private static let swatchSize = 18.0
    private static let hintSize = 16.0
    private static let hintGap = 3.0
    private static let profileIconSize = 14.0

    private let text: NSAttributedString
    private let profile: NSAttributedString
    private let hints: [PickerHint]

    init(_ label: PickerLabel) {
        let text = NSMutableAttributedString(string: label.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.black,
        ])
        text.append(NSAttributedString(string: "  •  ", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor(white: 0.8, alpha: 1),
            .baselineOffset: 1,
        ]))
        text.append(NSAttributedString(string: label.value, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.5, alpha: 1),
        ]))
        self.text = text
        profile = NSAttributedString(string: label.profile.displayName, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
        ])
        hints = label.hints
    }

    private var primaryWidth: Double {
        let hintsWidth = hints.isEmpty ? 0 : 8 + Double(hints.count) * Self.hintSize + Double(hints.count - 1) * Self.hintGap
        return 5 + Self.swatchSize + 8 + ceil(text.size().width) + hintsWidth + 12
    }

    private var secondaryWidth: Double {
        10 + Self.profileIconSize + 6 + ceil(profile.size().width) + 12
    }

    var size: CGSize {
        CGSize(width: max(primaryWidth, secondaryWidth), height: Self.primaryHeight + Self.pillGap + Self.secondaryHeight)
    }

    func draw(in rect: CGRect, swatch: CGColor?) {
        let primary = CGRect(
            x: rect.midX - primaryWidth / 2, y: rect.maxY - Self.primaryHeight, width: primaryWidth, height: Self.primaryHeight)
        let secondary = CGRect(
            x: rect.midX - secondaryWidth / 2, y: rect.minY, width: secondaryWidth, height: Self.secondaryHeight)
        drawPrimary(in: primary, swatch: swatch)
        drawSecondary(in: secondary)
    }

    private func drawPrimary(in rect: CGRect, swatch: CGColor?) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        var x = rect.minX + 5
        let swatchRect = CGRect(x: x, y: rect.midY - Self.swatchSize / 2, width: Self.swatchSize, height: Self.swatchSize)
        let circle = NSBezierPath(ovalIn: swatchRect)
        (swatch.flatMap(NSColor.init(cgColor:)) ?? NSColor(white: 0.5, alpha: 1)).setFill()
        circle.fill()
        NSColor(white: 0, alpha: 0.1).setStroke()
        circle.lineWidth = 1
        circle.stroke()
        x = swatchRect.maxX + 8

        let textSize = text.size()
        text.draw(at: CGPoint(x: x, y: rect.midY - textSize.height / 2))
        x += ceil(textSize.width) + 8

        for hint in hints {
            drawHint(hint, in: CGRect(x: x, y: rect.midY - Self.hintSize / 2, width: Self.hintSize, height: Self.hintSize))
            x += Self.hintSize + Self.hintGap
        }
    }

    /// A small rounded badge with the hint's symbol, white on black.
    private func drawHint(_ hint: PickerHint, in rect: CGRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let name = switch hint {
        case .multi: "square.stack.3d.up.fill"
        case .send: "paperplane.fill"
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 8.5, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = image.size
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    private func drawSecondary(in rect: CGRect) {
        NSColor(white: 0.08, alpha: 0.8).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        let icon = CGRect(
            x: rect.minX + 10, y: rect.midY - Self.profileIconSize / 2, width: Self.profileIconSize, height: Self.profileIconSize)
        drawGamutTriangle(in: icon)
        let size = profile.size()
        profile.draw(at: CGPoint(x: icon.maxX + 6, y: rect.midY - size.height / 2))
    }

    /// The profile icon: a rounded triangle filled with a rainbow, like a chromaticity diagram.
    private func drawGamutTriangle(in rect: CGRect) {
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: rect.midX, y: rect.maxY - 1))
        triangle.line(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY + 1))
        triangle.line(to: CGPoint(x: rect.minX + 0.5, y: rect.minY + 1))
        triangle.close()
        triangle.lineJoinStyle = .round
        NSGraphicsContext.saveGraphicsState()
        triangle.addClip()
        NSGradient(colors: [.systemPurple, .systemRed, .systemOrange, .systemYellow, .systemGreen])?
            .draw(in: rect, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
        triangle.lineWidth = 1.5
        NSColor(white: 1, alpha: 0.9).setStroke()
        triangle.stroke()
    }
}
