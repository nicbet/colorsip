import AppKit
import ColorsipCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Profiles (`spec.md` §6, §10): the Smart Profiles table and the fallback profile.
struct ProfilesPane: View {
    let settings: SettingsStore

    private var profiles: SmartProfiles { settings.settings.profiles }

    var body: some View {
        Form {
            Section {
                Picker("Other apps", selection: Binding(
                    get: { profiles.fallback },
                    set: { value in settings.update { $0.profiles.fallback = value } }
                )) {
                    ForEach(TargetProfile.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                note("Picked colors are converted to the profile of the app under the pointer.")
            }
            Section {
                ForEach(profiles.rules, id: \.bundleID) { rule in
                    row(rule)
                }
                HStack {
                    Menu("Add App") { addMenu }
                        .fixedSize()
                    Spacer()
                    Button("Restore Defaults") { settings.update { $0.profiles.restoreDefaults() } }
                        .disabled(profiles.rules == SmartProfiles.defaultRules)
                }
            } header: {
                Text("Apps")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ rule: ProfileRule) -> some View {
        LabeledContent {
            HStack {
                Picker(rule.name, selection: Binding(
                    get: { rule.profile },
                    set: { value in
                        settings.update { $0.profiles.setRule(bundleID: rule.bundleID, name: rule.name, profile: value) }
                    }
                )) {
                    ForEach(TargetProfile.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button {
                    settings.update { $0.profiles.removeRule(bundleID: rule.bundleID) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(rule.name)")
            }
        } label: {
            Label {
                Text(rule.name)
                Text(rule.bundleID)
            } icon: {
                Image(nsImage: Self.icon(for: rule.bundleID))
            }
        }
    }

    @ViewBuilder private var addMenu: some View {
        let running = runningApps
        ForEach(running, id: \.bundleIdentifier) { app in
            Button {
                add(bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!)
            } label: {
                Label {
                    Text(app.localizedName ?? app.bundleIdentifier!)
                } icon: {
                    Image(nsImage: Self.menuIcon(app.icon))
                }
            }
        }
        if !running.isEmpty { Divider() }
        Button("Choose…") { chooseApp() }
    }

    /// Running apps with a Dock icon that aren't in the table yet.
    private var runningApps: [NSRunningApplication] {
        let listed = Set(profiles.rules.map { $0.bundleID.lowercased() })
        let own = Bundle.main.bundleIdentifier?.lowercased()
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier?.lowercased() else { return false }
                return id != own && !listed.contains(id)
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
            let bundleID = bundle.bundleIdentifier
        else { return }
        add(bundleID: bundleID, name: FileManager.default.displayName(atPath: url.path).replacing(/\.app$/, with: ""))
    }

    /// New rows start on the fallback; an app already listed keeps its row.
    private func add(bundleID: String, name: String) {
        settings.update { settings in
            guard settings.profiles.rules.allSatisfy({ $0.bundleID.caseInsensitiveCompare(bundleID) != .orderedSame })
            else { return }
            settings.profiles.setRule(bundleID: bundleID, name: name, profile: settings.profiles.fallback)
        }
    }

    private static func icon(for bundleID: String) -> NSImage {
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        image.size = NSSize(width: 20, height: 20)
        return image
    }

    private static func menuIcon(_ icon: NSImage?) -> NSImage {
        let image = (icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).copy() as! NSImage
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

private extension TargetProfile {
    /// The fallback picker's titles.
    var title: String {
        self == .displayP3 ? "Display P3 (no conversion)" : displayName
    }
}

private func note(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
}
