import AppKit
import ColorsipCore
import SwiftUI

/// The single main window (`spec.md` §3.2). In the MVP it only has the Settings tab.
@MainActor
final class MainWindowController {
    private let model: AppModel
    private lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: MainWindowView(model: model)))
        window.title = "Colorsip"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 360))
        window.center()
        return window
    }()

    init(model: AppModel) {
        self.model = model
    }

    /// Opens the window on `tab`, or brings it forward if it's already open.
    func show(_ tab: MainWindowTab) {
        model.mainWindowTab = tab
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct MainWindowView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.mainWindowTab) {
            ForEach(MainWindowTab.visible(for: .current), id: \.self) { tab in
                content(tab)
                    .tabItem { Text(tab.title) }
                    .tag(tab)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
    }

    @ViewBuilder private func content(_ tab: MainWindowTab) -> some View {
        switch tab {
        case .library: EmptyView() // V2
        case .settings: SettingsTab(launchAtLogin: model.launchAtLogin)
        }
    }
}

/// Stub for the Settings tab; cs-7f6ead fills it out (`spec.md` §10).
struct SettingsTab: View {
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.requiresApproval {
                    Text("Allow Colorsip in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = launchAtLogin.lastError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        // Pick up changes made in System Settings while the window was closed.
        .onAppear { launchAtLogin.refresh() }
    }
}

extension MainWindowTab {
    var title: String {
        switch self {
        case .library: "Library"
        case .settings: "Settings"
        }
    }
}
