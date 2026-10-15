import Foundation

/// The label shown while the pointer is over a swatch: `name (value)` in the active format, or
/// `Copied` for a moment after a copy.
public struct SwatchHoverLabel: Equatable, Sendable {
    public var text: String

    public init(swatch: Swatch, format: OutputFormat, copied: Bool = false) {
        let value = format.string(for: swatch.color)
        text = copied ? "Copied" : swatch.name.isEmpty ? value : "\(swatch.name) (\(value))"
    }
}

/// Which swatch the pointer is over. Moving across a strip can deliver the next swatch's enter
/// before the previous one's exit, so an exit only counts for the swatch that's hovered.
public struct SwatchHoverTracker: Equatable, Sendable {
    public private(set) var hovered: Swatch.ID?

    public init() {}

    public mutating func enter(_ id: Swatch.ID) {
        hovered = id
    }

    public mutating func exit(_ id: Swatch.ID) {
        if hovered == id { hovered = nil }
    }

    public mutating func clear() {
        hovered = nil
    }
}

/// Where the hover label goes, in screen coordinates (y grows upward).
public enum HoverLabelPlacement {
    /// Centered above `anchor`, or below it when there's no room above, and kept inside
    /// `visibleFrame` horizontally.
    public static func frame(labelSize: CGSize, anchor: CGRect, visibleFrame: CGRect, gap: Double) -> CGRect {
        var y = anchor.maxY + gap
        if y + labelSize.height > visibleFrame.maxY {
            y = anchor.minY - gap - labelSize.height
        }
        let centered = anchor.midX - labelSize.width / 2
        let x = max(visibleFrame.minX, min(centered, visibleFrame.maxX - labelSize.width))
        return CGRect(origin: CGPoint(x: x, y: y), size: labelSize)
    }
}
