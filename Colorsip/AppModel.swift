import ColorsipCore
import Observation

/// State shared by the popover and the main window.
@MainActor
@Observable
final class AppModel {
    let launchAtLogin: LaunchAtLogin
    /// In memory only; cs-7f6ead persists it as the default format.
    var outputFormat: OutputFormat = .default
    var mainWindowTab: MainWindowTab = .settings

    init(loginItemService: any LoginItemService) {
        launchAtLogin = LaunchAtLogin(service: loginItemService)
    }
}
