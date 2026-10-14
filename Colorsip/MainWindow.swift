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
        window.setContentSize(NSSize(width: 560, height: 420))
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
        let tabs = MainWindowTab.visible(for: .current)
        Group {
            // A tab bar with a single tab (the MVP) would only add a second row of tabs above
            // the Settings panes.
            if tabs.count == 1, let tab = tabs.first {
                content(tab)
            } else {
                TabView(selection: $model.mainWindowTab) {
                    ForEach(tabs, id: \.self) { tab in
                        content(tab)
                            .tabItem { Text(tab.title) }
                            .tag(tab)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
    }

    @ViewBuilder private func content(_ tab: MainWindowTab) -> some View {
        switch tab {
        case .library: EmptyView() // V2
        case .settings: SettingsTab(model: model)
        }
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
