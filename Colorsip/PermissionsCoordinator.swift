import AppKit
import ColorsipCore
import Observation
import SwiftUI

/// Shows the permissions onboarding guide (`spec.md` §9) in its own window while
/// `Permissions.guide` is set, and keeps the status fresh.
@MainActor
final class PermissionsCoordinator: NSObject, NSWindowDelegate {
    private let permissions: Permissions
    private let system: SystemPermissionChecker
    private var window: NSWindow?
    private var pollTimer: Timer?

    init(permissions: Permissions, system: SystemPermissionChecker) {
        self.permissions = permissions
        self.system = system
        super.init()
        // Permissions granted or revoked while Colorsip was in the background.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [permissions] _ in
            MainActor.assumeIsolated { permissions.refresh() }
        }
        observeGuide()
    }

    func checkAtLaunch() {
        permissions.checkAtLaunch()
    }

    /// Starts the guide on every missing permission (Settings ▸ Permissions).
    func startGuide() {
        if permissions.startGuide() { bringWindowForward() }
    }

    /// For a feature that needs `permission`: `true` if it's granted, otherwise opens the guide on
    /// it and returns `false`.
    func require(_ permission: Permission) -> Bool {
        let granted = permissions.require(permission)
        if !granted { bringWindowForward() }
        return granted
    }

    /// Brings an open guide window to the front. A window that isn't open yet appears once the
    /// guide change is observed.
    private func bringWindowForward() {
        guard let window, window.isVisible else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Window

    private func observeGuide() {
        withObservationTracking {
            _ = permissions.guide != nil
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncWindow()
                self?.observeGuide()
            }
        }
    }

    private func syncWindow() {
        if permissions.guide == nil {
            window?.close()
        } else if window?.isVisible != true {
            showWindow()
        }
    }

    private func showWindow() {
        if window == nil {
            let view = PermissionGuideView(permissions: permissions, actions: PermissionGuideActions(
                openSettings: { [system] permission in
                    system.register(permission)
                    system.openSettings(for: permission)
                },
                skip: { [permissions] in permissions.skip() },
                relaunch: relaunch,
                done: { [permissions] in permissions.closeGuide() }
            ))
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Colorsip Permissions"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // Stays visible above System Settings while the user turns the permission on.
            window.level = .floating
            window.delegate = self
            window.center()
            self.window = window
        }
        if pollTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [permissions] _ in
                MainActor.assumeIsolated { permissions.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        // Closing the window isn't skipping.
        permissions.closeGuide()
    }

    /// Quits and starts Colorsip again, for when macOS only reports Screen Recording after a
    /// relaunch. The new instance starts once this one has exited, so the two never compete for
    /// the status item or the global shortcuts.
    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
            Bundle.main.bundleURL.path,
        ]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }
}
