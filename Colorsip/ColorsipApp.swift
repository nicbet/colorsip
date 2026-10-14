import AppKit
import ColorsipCore
import SwiftUI

@main
struct ColorsipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Agent app (LSUIElement): no Dock icon and no windows at launch. The UI is the status item
        // and the main window, both managed by AppKit in AppDelegate; SwiftUI needs one scene.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel(loginItemService: SMAppServiceLoginItem())
    private var mainWindow: MainWindowController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainWindow = MainWindowController(model: model)
        self.mainWindow = mainWindow
        statusItem = StatusItemController(model: model, actions: PopoverActions(
            picker: {},     // cs-40b6c9
            newPalette: {}, // cs-d6bd2c
            settings: { mainWindow.show(.settings) },
            quit: { NSApp.terminate(nil) }
        ))
    }
}
