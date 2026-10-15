import AppKit
import ColorsipCore
import SwiftUI

/// The content of the small popover anchored to a palette row: a text edit, a delete confirmation
/// or the icon picker. If what it edits is gone (deleted, or undone), it closes without changing
/// anything.
struct LibraryEditView: View {
    let edit: LibraryEdit
    let model: AppModel

    private var library: LibraryController { model.library }

    var body: some View {
        Group {
            if let content {
                content
            } else {
                Color.clear.frame(width: 1, height: 1).onAppear(perform: close)
            }
        }
        .padding(12)
    }

    private var content: AnyView? {
        let lib = library.library
        switch edit {
        case .renamePalette(let id):
            guard let palette = lib.palette(id) else { return nil }
            return AnyView(TextEditForm(title: "Rename Palette", text: palette.name, close: close) {
                library.renamePalette(id, to: $0)
            })
        case .editDescription(let id):
            guard let palette = lib.palette(id) else { return nil }
            return AnyView(TextEditForm(
                title: "Description", text: palette.description ?? "", multiline: true, close: close
            ) {
                library.setDescription($0, of: id)
            })
        case .setIcon(let id):
            guard let palette = lib.palette(id) else { return nil }
            return AnyView(IconPicker(current: palette.icon) { icon in
                library.setIcon(icon, of: id)
                close()
            })
        case .confirmDeletePalette(let id):
            guard let palette = lib.palette(id) else { return nil }
            let count = palette.allSwatches.count
            return AnyView(Confirmation(
                title: "Delete “\(palette.name)”?",
                message: "This deletes its \(count) \(count == 1 ? "color" : "colors").",
                actions: [.init(title: "Delete", role: .destructive) { library.deletePalette(id) }],
                close: close))
        case .renameGroup(let group, let paletteID):
            guard let g = lib.palette(paletteID)?.groups.first(where: { $0.id == group }) else { return nil }
            return AnyView(TextEditForm(title: "Rename Group", text: g.name, close: close) {
                library.renameGroup(group, in: paletteID, to: $0)
            })
        case .deleteGroup(let group, let paletteID):
            guard let g = lib.palette(paletteID)?.groups.first(where: { $0.id == group }) else { return nil }
            return AnyView(Confirmation(
                title: "Delete group “\(g.name)”?",
                message: "Its colors can be deleted too, or moved to the ungrouped section.",
                actions: [
                    .init(title: "Delete Colors", role: .destructive) {
                        library.deleteGroup(group, in: paletteID, keepSwatches: false)
                    },
                    .init(title: "Move Colors to Ungrouped") {
                        library.deleteGroup(group, in: paletteID, keepSwatches: true)
                    },
                ],
                close: close))
        case .renameSwatch(let id, let section):
            guard let swatch = lib.palette(section.palette)?.swatches(in: section.group)?.first(where: { $0.id == id })
            else { return nil }
            return AnyView(TextEditForm(title: "Rename Color", text: swatch.name, close: close) {
                library.renameSwatch(id, in: section, to: $0)
            })
        }
    }

    private func close() {
        if model.edit == edit { model.edit = nil }
    }
}

/// A title, a text field, and Cancel / Save. Return saves (Option-Return adds a line in a multiline
/// field) and Esc cancels.
private struct TextEditForm: View {
    let title: String
    @State var text: String
    var multiline = false
    let close: () -> Void
    let save: (String) -> Void

    @FocusState private var focused: Bool

    init(title: String, text: String, multiline: Bool = false, close: @escaping () -> Void, save: @escaping (String) -> Void) {
        self.title = title
        _text = State(initialValue: text)
        self.multiline = multiline
        self.close = close
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Group {
                if multiline {
                    TextField(title, text: $text, axis: .vertical).lineLimit(3...6)
                } else {
                    TextField(title, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .focused($focused)
            .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Button("Save", action: commit).keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 240)
        .onAppear { focused = true }
    }

    private func commit() {
        save(text)
        close()
    }
}

/// A title, a message, and buttons for each action plus Cancel.
private struct Confirmation: View {
    struct Action {
        var title: String
        var role: ButtonRole?
        var perform: () -> Void
    }

    let title: String
    let message: String
    let actions: [Action]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                ForEach(actions.indices, id: \.self) { i in
                    Button(actions[i].title, role: actions[i].role) {
                        actions[i].perform()
                        close()
                    }
                }
            }
        }
        .frame(width: 280)
    }
}

/// Picks a palette icon: one emoji, an SF Symbol from the curated list, or none.
private struct IconPicker: View {
    let current: PaletteIcon?
    let choose: (PaletteIcon?) -> Void

    @State private var emoji = ""
    @State private var query = ""
    @FocusState private var emojiFocused: Bool

    /// The curated symbols this system can draw.
    private static let available = PaletteIcon.curatedSymbols.filter {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon").font(.headline)
            HStack {
                TextField("Emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .focused($emojiFocused)
                    .onSubmit(chooseEmoji)
                    .onChange(of: emoji) { _, new in
                        if PaletteIcon.emoji(from: new) != nil { chooseEmoji() }
                    }
                Button {
                    emojiFocused = true
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Image(systemName: "face.smiling")
                }
                .help("Show Emoji & Symbols")
            }
            if !emoji.isEmpty && PaletteIcon.emoji(from: emoji) == nil {
                Text("Enter a single emoji.").font(.caption).foregroundStyle(.red)
            }
            TextField("Search symbols", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8), spacing: 4) {
                    ForEach(symbols, id: \.self) { name in
                        Button { choose(.symbol(name)) } label: {
                            Image(systemName: name)
                                .frame(width: 28, height: 28)
                                .background(
                                    current == .symbol(name) ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 160)
            HStack {
                Button("No Icon") { choose(nil) }
                    .disabled(current == nil)
                Spacer()
            }
        }
        .frame(width: 260)
        .onAppear {
            if case .emoji(let value) = current { emoji = value }
        }
    }

    private var symbols: [String] {
        let matching = Set(PaletteIcon.symbols(matching: query))
        return Self.available.filter(matching.contains)
    }

    private func chooseEmoji() {
        guard let icon = PaletteIcon.emoji(from: emoji), icon != current else { return }
        choose(icon)
    }
}
