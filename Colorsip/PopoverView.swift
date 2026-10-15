import ColorsipCore
import SwiftUI

struct PopoverActions {
    var picker: @MainActor () -> Void
    var newPalette: @MainActor () -> Void
    var settings: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

/// The menubar popover (`spec.md` §3.1): toolbar, format dropdown, palette list, bottom bar.
struct PopoverView: View {
    @Bindable var model: AppModel
    let actions: PopoverActions

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(PopoverItem.toolbar(for: .current), id: \.self, content: button)
            }
            .padding(10)

            formatMenu
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            PaletteListView(model: model)

            HStack {
                ForEach(PopoverItem.bottomBar(for: .current), id: \.self, content: button)
            }
            .padding(10)
        }
        .frame(width: 320)
        .background { undoRedoKeys }
        // The drag session clears the drag when it ends; closing the popover does too, in case it
        // closes mid-drag.
        .onDisappear { model.drag = nil }
    }

    /// Cmd+Z and Shift+Cmd+Z for library changes (`spec.md` §7.6), as invisible buttons so their key
    /// equivalents work while the popover is key.
    private var undoRedoKeys: some View {
        ZStack {
            Button("Undo") { model.library.undo() }
                .keyboardShortcut("z")
                .disabled(!model.library.canUndo)
            Button("Redo") { model.library.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.library.canRedo)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The active output format: a quiet rounded field with a small chevron instead of the stock
    /// menu picker's accent-colored up/down indicator.
    private var formatMenu: some View {
        Menu {
            Picker("Format", selection: $model.outputFormat) {
                ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack {
                Text(model.outputFormat.displayName)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func button(_ item: PopoverItem) -> some View {
        Button(action: action(item)) {
            Label(item.title, systemImage: item.systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help(item.title)
        .frame(maxWidth: item == .quit ? .infinity : nil, alignment: .trailing)
    }

    private func action(_ item: PopoverItem) -> @MainActor () -> Void {
        switch item {
        case .picker: actions.picker
        case .newPalette: actions.newPalette
        case .settings: actions.settings
        case .quit: actions.quit
        case .contrastChecker, .visionSimulation, .visionMode, .openMainWindow: {} // V2
        }
    }
}

extension PopoverItem {
    var title: String {
        switch self {
        case .picker: "Pick a Color"
        case .contrastChecker: "Contrast Checker"
        case .newPalette: "New Palette"
        case .visionSimulation: "Color Vision Simulation"
        case .settings: "Settings"
        case .visionMode: "Color Vision Mode"
        case .openMainWindow: "Open Main Window"
        case .quit: "Quit Colorsip"
        }
    }

    var systemImage: String {
        switch self {
        case .picker: "eyedropper"
        case .contrastChecker: "circle.lefthalf.filled"
        case .newPalette: "plus"
        case .visionSimulation: "eye"
        case .settings: "gearshape"
        case .visionMode: "eye.circle"
        case .openMainWindow: "macwindow"
        case .quit: "power"
        }
    }
}
