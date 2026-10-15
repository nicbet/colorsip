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
        for issue in model.library.loadIssues + [model.history.loadIssue].compactMap({ $0 }) {
            libraryLog.error("Library load issue: \(String(describing: issue), privacy: .public)")
        }
        let mainWindow = MainWindowController(model: model)
        self.mainWindow = mainWindow
        let permissionsGuide = PermissionsCoordinator(permissions: model.permissions, system: systemPermissions)
        self.permissionsGuide = permissionsGuide
        model.startPermissionsGuide = { permissionsGuide.startGuide() }
        let pickerController = PickerController(model: model)
        self.pickerController = pickerController
        pickerController.onPick = { [model] color in model.didPick(color) }
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
        let statusItem = StatusItemController(model: model, actions: PopoverActions(
            picker: picker,
            repick: { [model] in
                guard permissionsGuide.require(.screenRecording) else {
                    model.endRepick(nil)
                    model.discardEditor()
                    return
                }
                pickerController.open { [weak self] color in
                    model.endRepick(color)
                    self?.statusItem?.showPopover()
                }
            },
            newPalette: { [model] in model.newPalette() },
            settings: { mainWindow.show(.settings) },
            quit: { NSApp.terminate(nil) }
        ))
        self.statusItem = statusItem
        permissionsGuide.checkAtLaunch()
    }
}
