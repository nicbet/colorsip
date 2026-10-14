/// Where copied values go: the system pasteboard in the app, a fake in tests.
@MainActor
public protocol Clipboard {
    /// Replaces the clipboard's contents with `string`.
    func setString(_ string: String)
}

/// Copies `color` written in `format` (`spec.md` §3.1: click a swatch, Copy as…).
@MainActor
public func copyValue(of color: CSipColor, as format: OutputFormat, to clipboard: some Clipboard) {
    clipboard.setString(format.string(for: color))
}

extension CSipColor {
    /// This color gamut-mapped to Display P3, for drawing it on screen.
    public var displayP3Components: (red: Double, green: Double, blue: Double, alpha: Double) {
        let c = gamutMapped(to: .displayP3).components
        return (c[0], c[1], c[2], alpha)
    }
}
