import AppKit
import ColorsipCore
import OSLog
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
    private let systemPermissions = SystemPermissionChecker()
    private lazy var model = AppModel(
        loginItemService: SMAppServiceLoginItem(),
        hotKeyRegistrar: CarbonHotKeyRegistrar(),
        permissionChecker: systemPermissions
    )
    private var mainWindow: MainWindowController?
    private var statusItem: StatusItemController?
    private var permissionsGuide: PermissionsCoordinator?
    private var pickerController: PickerController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let libraryLog = Logger(subsystem: "com.nicolas-bettenburg.colorsip", category: "library")
        for issue in model.library.loadIssues {
            libraryLog.error("Library load issue: \(String(describing: issue), privacy: .public)")
        }
        let mainWindow = MainWindowController(model: model)
        self.mainWindow = mainWindow
        let permissionsGuide = PermissionsCoordinator(permissions: model.permissions, system: systemPermissions)
        self.permissionsGuide = permissionsGuide
        model.startPermissionsGuide = { permissionsGuide.startGuide() }
        let pickerController = PickerController(model: model)
        self.pickerController = pickerController
        // Until pick routing (cs-995046), a pick only copies its value.
        pickerController.onPick = { [model] color in model.copy(color) }
        let picker: @MainActor () -> Void = {
            guard permissionsGuide.require(.screenRecording) else { return }
            pickerController.open()
        }
        model.shortcuts.onTrigger = { action in
            switch action {
            case .picker: picker()
            case .contrastChecker, .mainWindow: break // V2
            }
        }
        statusItem = StatusItemController(model: model, actions: PopoverActions(
            picker: picker,
            newPalette: {}, // cs-d6bd2c
            settings: { mainWindow.show(.settings) },
            quit: { NSApp.terminate(nil) }
        ))
        permissionsGuide.checkAtLaunch()
    }
}
