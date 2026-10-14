import AppKit
import ColorsipCore
import SwiftUI

/// The Settings tab of the main window (`spec.md` §10): one tab per pane.
struct SettingsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsPane) {
            ForEach(SettingsPane.visible(for: .current), id: \.self) { pane in
                content(pane)
                    .tabItem { Label(pane.title, systemImage: pane.systemImage) }
                    .tag(pane)
            }
        }
    }

    @ViewBuilder private func content(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane(model: model)
        case .shortcuts: ShortcutsPane(shortcuts: model.shortcuts)
        case .picker: PickerPane(settings: model.settings)
        case .permissions: PermissionsPane(model: model)
        case .profiles, .formats, .sync: EmptyView() // cs-615265, V3
        }
    }
}

private struct PermissionsPane: View {
    let model: AppModel

    private var permissions: Permissions { model.permissions }

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases, id: \.self) { permission in
                    LabeledContent {
                        let granted = permissions.isGranted(permission)
                        Label(granted ? "Granted" : "Not granted",
                              systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(granted ? .green : .secondary)
                    } label: {
                        Text(permission.title)
                        Text(permission.explanation)
                    }
                }
            }
            if !permissions.missing.isEmpty {
                Section {
                    Button("Start Guide Again") { model.startPermissionsGuide() }
                }
            }
        }
        .formStyle(.grouped)
        // The app refreshes when it becomes active; this covers switching panes.
        .onAppear { permissions.refresh() }
    }
}

private struct GeneralPane: View {
    @Bindable var model: AppModel

    private var launchAtLogin: LaunchAtLogin { model.launchAtLogin }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.requiresApproval {
                    note("Allow Colorsip in System Settings → General → Login Items.")
                }
                if let error = launchAtLogin.lastError {
                    note(error.localizedDescription, isError: true)
                }
                Picker("Default format", selection: $model.outputFormat) {
                    ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                }
            }
            if let message = settingsMessage {
                Section { note(message, isError: true) }
            }
            Section {
                Button("Quit Colorsip") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        // Pick up changes made in System Settings while the window was closed.
        .onAppear { launchAtLogin.refresh() }
    }

    private var settingsMessage: String? {
        switch model.settings.loadIssue {
        case .newerFormat:
            return "settings.json was saved by a newer version of Colorsip. Changes made here won't be saved."
        case .unreadable:
            return "settings.json couldn't be read. Colorsip uses the default settings and won't overwrite the file."
        case nil:
            return model.settings.lastError.map { "Settings couldn't be saved: \($0.localizedDescription)" }
        }
    }
}

private struct ShortcutsPane: View {
    let shortcuts: ShortcutManager

    var body: some View {
        Form {
            Section {
                ForEach(shortcuts.actions, id: \.self) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(action: action, manager: shortcuts)
                    }
                }
            } footer: {
                Text("Click a shortcut, then press the new key combination. Esc cancels, ⌫ removes the shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PickerPane: View {
    let settings: SettingsStore

    private var loupe: LoupeSettings { settings.settings.loupe }

    var body: some View {
        Form {
            Section {
                LabeledContent("Loupe diameter") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(loupe.diameter) },
                                set: { value in settings.update { $0.loupe.diameter = Int(value) } }),
                            in: Double(LoupeSettings.diameterRange.lowerBound)...Double(LoupeSettings.diameterRange.upperBound),
                            step: Double(LoupeSettings.diameterStep))
                        Text("\(loupe.diameter) pt")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                LabeledContent("Grid size") {
                    Stepper(
                        "\(loupe.gridSize) × \(loupe.gridSize) pixels",
                        value: Binding(
                            get: { loupe.gridSize },
                            set: { value in settings.update { $0.loupe.gridSize = value } }),
                        in: LoupeSettings.gridSizeRange, step: 2)
                    .monospacedDigit()
                }
            } footer: {
                Text("While picking, the mouse wheel changes the diameter and Option + wheel the grid size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private func note(_ text: String, isError: Bool = false) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(isError ? .red : .secondary)
}

extension SettingsPane {
    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .picker: "Picker"
        case .profiles: "Profiles"
        case .permissions: "Permissions"
        case .formats: "Formats"
        case .sync: "Sync"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .picker: "eyedropper"
        case .profiles: "paintpalette"
        case .permissions: "lock.shield"
        case .formats: "textformat"
        case .sync: "arrow.triangle.2.circlepath"
        }
    }
}
