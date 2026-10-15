import ColorsipCore
import SwiftUI

/// The compact color editor (`spec.md` §5.4): it takes the popover over, like a sheet, and edits a
/// draft (``ColorEditor``) that only reaches the library on Done. The controls are thin views over
/// the draft; the rules live in ColorsipCore.
struct ColorEditorView: View {
    @Bindable var model: AppModel
    /// Starts the eyedropper. The popover closes meanwhile and comes back with the editor.
    let repick: @MainActor () -> Void

    var body: some View {
        if let session = model.colorEditor {
            content(session.editor, duplicateName: session.duplicateName)
                .padding(12)
                .onChange(of: session.editor.color) { model.colorEditor?.duplicateName = nil }
        }
    }

    private func content(_ editor: ColorEditor, duplicateName: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Edit Color").font(.headline)
                Spacer()
                moreMenu(editor)
            }

            HStack(alignment: .top, spacing: 10) {
                SaturationBrightnessField(editor: editor) { s, b in
                    update { $0.setSaturation(s, brightness: b) }
                }
                .frame(height: 150)
                VStack(spacing: 8) {
                    ColorPreview(before: editor.original.color, after: editor.color)
                        .frame(width: 44, height: 104)
                    Button {
                        model.startRepick()
                        repick()
                    } label: {
                        Image(systemName: "eyedropper").frame(width: 20, height: 20)
                    }
                    .help("Pick the color from the screen")
                }
            }

            HueSlider(hue: editor.hsb.hue) { hue in update { $0.setHue(hue) } }
            AlphaSlider(color: editor.color, alpha: editor.color.alpha) { alpha in update { $0.setAlpha(alpha) } }

            if let duplicateName {
                Label("“\(duplicateName)” in this group already has this color.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Picker("Model", selection: $model.editorModel) {
                ForEach(EditorModel.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            NumericFields(editor: editor, editorModel: model.editorModel) { text, index in
                update { $0.commit(text, field: index, of: model.editorModel) }
            } commitAlpha: { text in
                update { $0.commitAlpha(text) }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                TextField("Name", text: Binding {
                    editor.name
                } set: { name in
                    update { $0.setName(name) }
                })
                Text("Description")
                    .padding(.top, 4)
                TextField("Add a description", text: Binding {
                    editor.description
                } set: { description in
                    update { $0.description = description }
                }, axis: .vertical)
                .lineLimit(1...3)
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.discardEditor() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { model.saveEditor() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The "…" menu: Copy as and Reset.
    private func moreMenu(_ editor: ColorEditor) -> some View {
        Menu {
            Menu("Copy as") {
                ForEach(OutputFormat.allCases) { format in
                    Button("\(format.displayName) — \(format.string(for: editor.color))") {
                        model.copy(editor.color, as: format)
                    }
                }
            }
            Button("Reset") { update { $0.reset() } }
                .disabled(!editor.hasChanges)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private func update(_ change: (inout ColorEditor) -> Void) {
        guard var editor = model.colorEditor?.editor else { return }
        change(&editor)
        model.colorEditor?.editor = editor
    }
}

// MARK: - Field and sliders

/// Saturation left to right and brightness bottom to top, at the draft's hue, in the working space.
private struct SaturationBrightnessField: View {
    let editor: ColorEditor
    let change: (Double, Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let (width, height) = (Double(proxy.size.width), Double(proxy.size.height))
            let hsb = editor.hsb
            let pure = CSipColor(hsb: HSB(hue: hsb.hue, saturation: 1, brightness: 1), in: editor.workingSpace)
            ZStack {
                Rectangle().fill(pure.swiftUIColor)
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
            .overlay(alignment: .topLeading) {
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 3))
                    .frame(width: 12, height: 12)
                    .offset(x: hsb.saturation * width - 6, y: (1 - hsb.brightness) * height - 6)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                change(value.location.x / width, 1 - value.location.y / height)
            })
        }
    }
}

private let sliderHeight = 14.0

/// A horizontal track with a round thumb; `value` is 0–1.
private struct SliderTrack<Track: View>: View {
    let value: Double
    let change: (Double) -> Void
    @ViewBuilder let track: () -> Track

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            track()
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                        .frame(width: sliderHeight, height: sliderHeight)
                        .offset(x: value * (width - sliderHeight))
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let x = (drag.location.x - sliderHeight / 2) / (width - sliderHeight)
                    change(min(max(x, 0), 1))
                })
        }
        .frame(height: sliderHeight)
    }
}

private struct HueSlider: View {
    let hue: Double
    let change: (Double) -> Void

    var body: some View {
        // 359.999 rather than 360, so dragging to the end doesn't wrap the thumb back to 0.
        SliderTrack(value: hue / 360, change: { change(min($0 * 360, 359.999)) }) {
            LinearGradient(
                colors: stride(from: 0.0, through: 360, by: 30).map {
                    CSipColor(hsb: HSB(hue: $0, saturation: 1, brightness: 1)).swiftUIColor
                },
                startPoint: .leading, endPoint: .trailing)
        }
        .help("Hue")
    }
}

private struct AlphaSlider: View {
    let color: CSipColor
    let alpha: Double
    let change: (Double) -> Void

    var body: some View {
        var opaque = color
        opaque.alpha = 1
        var clear = color
        clear.alpha = 0
        return SliderTrack(value: alpha, change: change) {
            ZStack {
                Checkerboard()
                LinearGradient(colors: [clear.swiftUIColor, opaque.swiftUIColor], startPoint: .leading, endPoint: .trailing)
            }
        }
        .help("Opacity")
    }
}

/// The color as it was when the editor opened, above the draft.
private struct ColorPreview: View {
    let before: CSipColor
    let after: CSipColor

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(before.swiftUIColor).help("Before")
            Rectangle().fill(after.swiftUIColor).help("After")
        }
        .background(Checkerboard())
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// Light and mid-gray squares behind translucent colors, in the editor and the swatch strips.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell = 5.0
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0..<Int((size.height / cell).rounded(.up)) {
                for column in 0..<Int((size.width / cell).rounded(.up)) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: Double(column) * cell, y: Double(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(white: 0.8)))
                }
            }
        }
    }
}

// MARK: - Numeric fields

/// The fields of the chosen model plus alpha. HEX, RGB and HSL warn when they show a mapped value.
private struct NumericFields: View {
    let editor: ColorEditor
    let editorModel: EditorModel
    let commit: (String, Int) -> Void
    let commitAlpha: (String) -> Void

    var body: some View {
        let values = editor.fields(editorModel)
        HStack(spacing: 6) {
            ForEach(Array(editorModel.fieldLabels.enumerated()), id: \.offset) { index, label in
                NumericField(label: label, value: values[index]) { commit($0, index) }
            }
            NumericField(label: "A", value: editor.alphaField, fieldWidth: 44, commit: commitAlpha)
            if editor.isOutsideSRGB && [.hex, .rgb, .hsl].contains(editorModel) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help("Outside sRGB — shown mapped")
            }
        }
        // A different model is a different set of fields; don't carry text over.
        .id(editorModel)
    }
}

/// A labeled text field that commits on Return or when it loses focus, and otherwise shows `value`.
private struct NumericField: View {
    let label: String
    let value: String
    /// A fixed width for the text field; otherwise the fields share the row.
    var fieldWidth: CGFloat?
    let commit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .monospacedDigit()
                .focused($focused)
                .onSubmit(apply)
                .frame(width: fieldWidth)
        }
        .onAppear { text = value }
        // The value only changes while typing if another control changed the draft.
        .onChange(of: value) { text = value }
        .onChange(of: focused) { if !focused { apply() } }
    }

    private func apply() {
        commit(text)
        // A rejected or clamped entry shows the value the draft ended up with.
        text = value
    }
}
