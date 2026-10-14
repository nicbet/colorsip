import AppKit
import ColorsipCore
import SwiftUI

/// The popover's palette list (`spec.md` §3.1): one row per palette, in library order.
struct PaletteListView: View {
    let model: AppModel

    var body: some View {
        let library = model.library.library
        if library.palettes.isEmpty {
            Text("No palettes yet. Click + to create one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(library.palettes) { palette in
                        PaletteRow(
                            palette: palette,
                            isPickTarget: library.pickTarget == palette.id,
                            format: model.outputFormat,
                            selectAsPickTarget: { model.setPickTarget(palette.id) },
                            copy: { model.copy($0, as: $1) })
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A palette's header (radio button or lock, icon, name) above its swatch strip.
struct PaletteRow: View {
    let palette: Palette
    let isPickTarget: Bool
    let format: OutputFormat
    let selectAsPickTarget: () -> Void
    let copy: (CSipColor, OutputFormat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                leadingSlot
                    .frame(width: 16)
                icon
                Text(palette.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if palette.allSwatches.isEmpty {
                DropColorsTarget()
            } else {
                SwatchStrip(palette: palette, format: format, copy: copy)
            }
        }
    }

    /// The pick-target radio button. A locked palette can't be the target, so it shows its lock here
    /// instead.
    @ViewBuilder private var leadingSlot: some View {
        if palette.isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help("Locked")
        } else {
            Button(action: selectAsPickTarget) {
                Image(systemName: isPickTarget ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isPickTarget ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help(isPickTarget ? "New picks go into this palette" : "Add new picks to this palette")
        }
    }

    @ViewBuilder private var icon: some View {
        switch palette.icon {
        case .emoji(let emoji): Text(emoji)
        case .symbol(let name): Image(systemName: name).foregroundStyle(.secondary)
        case nil: EmptyView()
        }
    }
}

private let stripHeight = 20.0
private let stripCornerRadius = 4.0

/// The dashed target an empty palette shows instead of a strip (`spec.md` §3.1).
struct DropColorsTarget: View {
    var body: some View {
        RoundedRectangle(cornerRadius: stripCornerRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.tertiary)
            .overlay {
                Text("Drop colors here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: stripHeight)
    }
}

/// A palette's swatches as fixed-width segments, one rounded run per section (`spec.md` §7.3). The
/// geometry comes from ``SwatchStripLayout``.
struct SwatchStrip: View {
    let palette: Palette
    let format: OutputFormat
    let copy: (CSipColor, OutputFormat) -> Void

    @State private var offset = 0.0
    @State private var copied: Swatch.ID?

    var body: some View {
        GeometryReader { proxy in
            let layout = SwatchStripLayout(palette: palette, width: proxy.size.width)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SwatchStripLayout.groupGap) {
                    ForEach(layout.sections) { section in
                        HStack(spacing: 0) {
                            ForEach(section.swatches) { swatch in
                                cell(swatch)
                                    .frame(width: layout.segmentWidth)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: stripCornerRadius))
                    }
                }
                .frame(height: stripHeight)
            }
            .scrollDisabled(!layout.isScrollable)
            .onScrollGeometryChange(for: Double.self) { $0.contentOffset.x + $0.contentInsets.leading } action: {
                offset = $1
            }
            .mask(fadeMask(layout.fades(offset: offset)))
            .animation(.easeOut(duration: 0.15), value: layout.fades(offset: offset))
        }
        .frame(height: stripHeight)
    }

    private func cell(_ swatch: Swatch) -> some View {
        Rectangle()
            .fill(swatch.color.swiftUIColor)
            .overlay {
                if copied == swatch.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(swatch.color.prefersDarkForeground ? .black : .white)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { copyAndConfirm(swatch, as: format) }
            .help("\(swatch.name) — \(format.string(for: swatch.color))")
            .contextMenu {
                Menu("Copy as") {
                    ForEach(OutputFormat.allCases) { format in
                        Button("\(format.displayName) — \(format.string(for: swatch.color))") {
                            copyAndConfirm(swatch, as: format)
                        }
                    }
                }
            }
    }

    /// Copies the value and shows a check mark on the swatch for about a second.
    private func copyAndConfirm(_ swatch: Swatch, as format: OutputFormat) {
        copy(swatch.color, format)
        withAnimation(.easeOut(duration: 0.1)) { copied = swatch.id }
        Task {
            try? await Task.sleep(for: .seconds(1))
            if copied == swatch.id { withAnimation { copied = nil } }
        }
    }

    /// Opaque in the middle, fading to clear on each edge that has more content beyond it.
    private func fadeMask(_ fades: SwatchStripLayout.Fades) -> some View {
        let fadeWidth = 16.0
        return HStack(spacing: 0) {
            LinearGradient(colors: [fades.leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
            Rectangle()
            LinearGradient(colors: [.black, fades.trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
        }
    }
}

extension CSipColor {
    var swiftUIColor: Color {
        let c = displayP3Components
        return Color(.displayP3, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    /// Whether black reads better than white on top of this color.
    var prefersDarkForeground: Bool {
        converted(to: .oklch).components[0] > 0.65
    }
}

/// The system pasteboard (`NSPasteboard.general`).
struct SystemClipboard: Clipboard {
    func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
