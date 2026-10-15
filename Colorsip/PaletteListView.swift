import AppKit
import ColorsipCore
import SwiftUI

/// The popover's palette list (`spec.md` §3.1): Color History first, then one row per palette, in
/// library order.
struct PaletteListView: View {
    let model: AppModel

    @State private var reorder = PaletteReorder()
    @State private var contentHeight = 0.0

    var body: some View {
        let library = model.library.library
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: rowSpacing) {
                    HistoryRow(
                        swatches: model.history.history.swatches,
                        format: model.outputFormat,
                        copy: { model.copy($0, as: $1) })
                    ForEach(library.palettes) { palette in
                        PaletteRow(
                            palette: palette,
                            isPickTarget: library.pickTarget == palette.id,
                            model: model,
                            reorder: reorder)
                            .id(palette.id)
                    }
                    if library.palettes.isEmpty {
                        Text("No palettes yet. Click + to create one.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .coordinateSpace(.named(paletteListSpace))
                .overlay(alignment: .topLeading) {
                    if let y = reorder.lineY(in: library.palettes.map(\.id)) {
                        Capsule()
                            .fill(.tint)
                            .frame(height: 2)
                            .offset(y: y - 1)
                    }
                }
                .listContainer()
                .padding(.horizontal, 10)
                .onGeometryChange(for: Double.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .onChange(of: model.edit) { _, edit in
                guard let edit else { return }
                withAnimation { scroller.scrollTo(edit.palette) }
            }
        }
        // As tall as the list, so the popover fits it, until it scrolls.
        .frame(height: min(contentHeight, maxListHeight))
    }
}

/// The tallest the list gets before it scrolls, which keeps the popover near 420 pt.
private let maxListHeight = 300.0

private let rowSpacing = 14.0
/// The coordinate space of the list's rows, for dragging palettes.
private let paletteListSpace = "paletteList"
/// The size of row labels: Color History's title and palette names.
private let labelFontSize = 12.0

/// Color History (`spec.md` §7.4): read-only, so no radio button, no lock and no icon.
struct HistoryRow: View {
    let swatches: [Swatch]
    let format: OutputFormat
    let copy: (CSipColor, OutputFormat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color History")
                .font(.system(size: labelFontSize))
            if swatches.isEmpty {
                StripPlaceholder(label: "Picked colors appear here")
            } else {
                SwatchStrip(swatches: swatches, format: format, copy: copy)
            }
        }
    }
}

extension View {
    /// The list's container: one rounded panel, white with black text in light mode and black with
    /// white text in dark mode, so colors sit on a neutral background.
    func listContainer() -> some View { modifier(ListContainer()) }
}

private struct ListContainer: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .foregroundStyle(isDark ? Color.white : Color.black)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isDark ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A palette's header (radio button or lock, icon, name) above its swatch strip. Right-clicking it
/// offers the palette menu (`spec.md` §3.1); dragging the header reorders the palettes. Edits open in
/// a small popover anchored to the row.
struct PaletteRow: View {
    let palette: Palette
    let isPickTarget: Bool
    let model: AppModel
    let reorder: PaletteReorder

    private var library: LibraryController { model.library }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                leadingSlot
                    .frame(width: 16)
                header
            }
            if palette.allSwatches.isEmpty {
                StripPlaceholder(label: "Drop colors here")
            } else {
                SwatchStrip(palette: palette, format: model.outputFormat, copy: { model.copy($0, as: $1) }) { swatch, group in
                    AnyView(swatchMenu(swatch, in: group))
                }
            }
        }
        .contentShape(Rectangle())
        .opacity(reorder.dragging == palette.id ? 0.4 : 1)
        .contextMenu { paletteMenu }
        .popover(item: editBinding, arrowEdge: .bottom) { LibraryEditView(edit: $0, model: model) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(paletteListSpace)) } action: {
            reorder.frames[palette.id] = $0
        }
        .onDisappear { reorder.frames[palette.id] = nil }
    }

    /// Dragging the header up or down moves the palette to the slot under the pointer.
    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(paletteListSpace))
            .onChanged { value in
                reorder.dragging = palette.id
                reorder.pointerY = value.location.y
            }
            .onEnded { _ in
                if let move = reorder.move(in: library.library.palettes.map(\.id)) {
                    library.movePalette(palette.id, before: move.before)
                }
                reorder.dragging = nil
            }
    }

    /// Icon and name, with the description as a tooltip. Clicking it makes the palette the pick
    /// target; it never clears it, only the radio button does.
    private var header: some View {
        HStack(spacing: 6) {
            icon
            Text(palette.name)
                .font(.system(size: labelFontSize))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { library.selectPickTarget(palette.id) }
        .gesture(reorderGesture)
        .help(palette.description ?? "")
    }

    /// The model's edit while it belongs to this row, so the popover shows here and nowhere else.
    private var editBinding: Binding<LibraryEdit?> {
        Binding {
            model.edit?.palette == palette.id ? model.edit : nil
        } set: { edit in
            if edit != nil || model.edit?.palette == palette.id { model.edit = edit }
        }
    }

    /// The pick-target radio button: clicking the current target clears it. A locked palette can't
    /// be the target, so it shows its lock here instead.
    @ViewBuilder private var leadingSlot: some View {
        if palette.isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help("Locked")
        } else {
            Button { library.togglePickTarget(palette.id) } label: {
                Image(systemName: isPickTarget ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isPickTarget ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help(isPickTarget ? "New picks go into this palette. Click to stop." : "Add new picks to this palette")
        }
    }

    @ViewBuilder private var paletteMenu: some View {
        ForEach(PaletteMenuItem.items(for: palette), id: \.self) { item in
            switch item {
            case .rename: Button("Rename…") { model.edit = .renamePalette(palette.id) }
            case .editDescription: Button("Edit Description…") { model.edit = .editDescription(palette.id) }
            case .setIcon: Button("Set Icon…") { model.edit = .setIcon(palette.id) }
            case .lock: Button("Lock") { library.setLocked(true, palette: palette.id) }
            case .unlock: Button("Unlock") { library.setLocked(false, palette: palette.id) }
            case .newGroup:
                Divider()
                Button("New Group…") {
                    if let group = library.newGroup(in: palette.id) {
                        model.edit = .renameGroup(group, in: palette.id)
                    }
                }
            case .groups:
                Menu("Groups") {
                    ForEach(palette.groups) { group in
                        Menu(group.name) { groupMenu(group) }
                    }
                }
            case .duplicate:
                Divider()
                Button("Duplicate") { library.duplicatePalette(palette.id) }
            case .delete:
                Button("Delete", role: .destructive) {
                    if palette.deletionNeedsConfirmation {
                        model.edit = .confirmDeletePalette(palette.id)
                    } else {
                        library.deletePalette(palette.id)
                    }
                }
            }
        }
    }

    @ViewBuilder private func groupMenu(_ group: SwatchGroup) -> some View {
        ForEach(GroupMenuItem.items(for: group.id, in: palette), id: \.self) { item in
            switch item {
            case .rename: Button("Rename…") { model.edit = .renameGroup(group.id, in: palette.id) }
            case .moveLeft: Button("Move Left") { library.moveGroup(group.id, in: palette.id, by: -1) }
            case .moveRight: Button("Move Right") { library.moveGroup(group.id, in: palette.id, by: 1) }
            case .delete:
                Button("Delete…", role: .destructive) {
                    if group.deletionNeedsChoice {
                        model.edit = .deleteGroup(group.id, in: palette.id)
                    } else {
                        library.deleteGroup(group.id, in: palette.id, keepSwatches: false)
                    }
                }
            }
        }
    }

    /// The swatch menu items after Copy as: Rename…, Delete and the group's submenu.
    @ViewBuilder private func swatchMenu(_ swatch: Swatch, in groupID: SwatchGroup.ID?) -> some View {
        let section = groupID.map { SectionID.group($0, in: palette.id) } ?? .ungrouped(palette.id)
        ForEach(SwatchMenuItem.items(in: groupID, of: palette), id: \.self) { item in
            switch item {
            case .copyAs: EmptyView() // drawn by the strip
            case .rename:
                Divider()
                Button("Rename…") { model.edit = .renameSwatch(swatch.id, in: section) }
            case .delete: Button("Delete", role: .destructive) { library.deleteSwatch(swatch.id, in: section) }
            case .group:
                if let group = palette.groups.first(where: { $0.id == groupID }) {
                    Divider()
                    Menu("Group “\(group.name)”") { groupMenu(group) }
                }
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch palette.icon {
        case .emoji(let emoji): Text(emoji).font(.system(size: labelFontSize))
        case .symbol(let name): Image(systemName: name).font(.system(size: labelFontSize)).foregroundStyle(.secondary)
        case nil: EmptyView()
        }
    }
}

private let stripHeight = 32.0
/// Room around a strip's segments so their shadow isn't clipped by the scroll view.
private let stripInset = 2.0
private let stripCornerRadius = 6.0

/// The dashed box shown instead of an empty strip: an empty palette's "Drop colors here" target
/// (`spec.md` §3.1), or an empty Color History.
struct StripPlaceholder: View {
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: stripCornerRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.tertiary)
            .overlay {
                Text(label)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(height: stripHeight)
            .padding(stripInset)
    }
}

/// Swatches as fixed-width segments, one rounded run per section (`spec.md` §7.3). The geometry
/// comes from ``SwatchStripLayout``.
struct SwatchStrip: View {
    private let makeLayout: (Double) -> SwatchStripLayout
    let format: OutputFormat
    let copy: (CSipColor, OutputFormat) -> Void
    /// Context menu items after Copy as, for a swatch in a group (`nil` for the ungrouped section).
    private let menu: (Swatch, SwatchGroup.ID?) -> AnyView

    @State private var offset = 0.0
    @State private var copied: Swatch.ID?

    /// A palette's strip: its ungrouped section, then each group.
    init(
        palette: Palette, format: OutputFormat, copy: @escaping (CSipColor, OutputFormat) -> Void,
        menu: @escaping (Swatch, SwatchGroup.ID?) -> AnyView
    ) {
        makeLayout = { SwatchStripLayout(palette: palette, width: $0) }
        self.format = format
        self.copy = copy
        self.menu = menu
    }

    /// One section of `swatches`, such as Color History. Its swatches only offer Copy as.
    init(swatches: [Swatch], format: OutputFormat, copy: @escaping (CSipColor, OutputFormat) -> Void) {
        makeLayout = { SwatchStripLayout(swatches: swatches, width: $0) }
        self.format = format
        self.copy = copy
        menu = { _, _ in AnyView(EmptyView()) }
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = makeLayout(proxy.size.width - 2 * stripInset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SwatchStripLayout.groupGap) {
                    ForEach(layout.sections) { section in
                        HStack(spacing: 0) {
                            ForEach(section.swatches) { swatch in
                                cell(swatch, in: section.group)
                                    .frame(width: layout.segmentWidth)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: stripCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: stripCornerRadius)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                    }
                }
                .frame(height: stripHeight)
                .padding(stripInset)
            }
            .scrollDisabled(!layout.isScrollable)
            .onScrollGeometryChange(for: Double.self) { $0.contentOffset.x + $0.contentInsets.leading } action: {
                offset = $1
            }
            .mask(fadeMask(layout.fades(offset: offset)))
            .animation(.easeOut(duration: 0.15), value: layout.fades(offset: offset))
        }
        .frame(height: stripHeight + 2 * stripInset)
    }

    private func cell(_ swatch: Swatch, in group: SwatchGroup.ID?) -> some View {
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
                menu(swatch, group)
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

/// A palette being dragged up or down the list (`spec.md` §7.1): the pointer's position and the
/// frames of the rows on screen, in the list's coordinate space.
@MainActor
@Observable
final class PaletteReorder {
    var dragging: Palette.ID?
    var pointerY = 0.0
    var frames: [Palette.ID: CGRect] = [:]

    /// The move a drop at the pointer would make, or `nil` if it would change nothing.
    func move(in ids: [Palette.ID]) -> ListReorder.Move<Palette.ID>? {
        guard let dragging, let slot = slot(in: ids) else { return nil }
        return ListReorder.move(dragging, to: slot, in: ids)
    }

    /// Where to draw the insertion line: centered in the gap at the slot, or `nil` when a drop would
    /// change nothing.
    func lineY(in ids: [Palette.ID]) -> Double? {
        guard move(in: ids) != nil, let slot = slot(in: ids) else { return nil }
        if slot < ids.count, let frame = frames[ids[slot]] { return frame.minY - rowSpacing / 2 }
        if slot > 0, let frame = frames[ids[slot - 1]] { return frame.maxY + rowSpacing / 2 }
        return nil
    }

    /// The slot under the pointer. Only rows on screen have frames, so the slot is found among them
    /// and mapped back to an index in `ids`.
    private func slot(in ids: [Palette.ID]) -> Int? {
        guard dragging != nil else { return nil }
        let visible: [(index: Int, frame: CGRect)] = ids.indices.compactMap { index in
            frames[ids[index]].map { (index, $0) }
        }
        guard let last = visible.last else { return nil }
        let slot = ListReorder.insertionIndex(at: pointerY, midpoints: visible.map { Double($0.frame.midY) })
        return slot < visible.count ? visible[slot].index : last.index + 1
    }
}

/// The system pasteboard (`NSPasteboard.general`).
struct SystemClipboard: Clipboard {
    func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
