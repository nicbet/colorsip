import ColorsipCore
import SwiftUI

struct PermissionGuideActions {
    var openSettings: @MainActor (Permission) -> Void
    var skip: @MainActor (Permission) -> Void
    var done: @MainActor () -> Void
}

/// The onboarding checklist (`spec.md` §9): every listed permission at once with its live status,
/// then "all set".
struct PermissionGuideView: View {
    let permissions: Permissions
    let actions: PermissionGuideActions

    var body: some View {
        Group {
            if let checklist = permissions.checklist {
                if permissions.isComplete {
                    allSet
                } else {
                    list(checklist)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func list(_ checklist: PermissionChecklist) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colorsip needs your permission")
                .font(.title2.bold())
            Text("Click Open System Settings, then turn on Colorsip in the list. Each row updates as soon as macOS reports the change.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(checklist.items, id: \.self) { permission in
                    row(permission, highlighted: checklist.highlighted == permission)
                }
            }
        }
    }

    private func row(_ permission: Permission, highlighted: Bool) -> some View {
        let status = permissions.status(of: permission)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 26))
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(permission.title).font(.headline)
                    if !permission.isSkippable && status != .granted {
                        Text("Required").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(permission.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if status != .granted {
                    HStack {
                        Button("Open System Settings") { actions.openSettings(permission) }
                        if status == .skipped {
                            Text("Skipped").foregroundStyle(.secondary)
                        } else if permission.isSkippable {
                            Button("Skip") { actions.skip(permission) }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if status == .granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(highlighted && status != .granted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
    }

    private var allSet: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("You're all set").font(.title2.bold())
            Text("Colorsip has the permissions it needs.")
                .foregroundStyle(.secondary)
            Button("Done") { actions.done() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
    }
}

extension Permission {
    var title: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        }
    }

    /// What the permission is for.
    var explanation: String {
        switch self {
        case .screenRecording:
            "The color picker reads the pixels under the pointer. macOS lists this as Screen & System Audio Recording. Colorsip never records or saves your screen."
        case .accessibility:
            "Cmd+click in the picker pastes the color into the app you were using. Sending that paste needs Accessibility. It's optional: without it, the color is only copied."
        }
    }

    var systemImage: String {
        switch self {
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        }
    }
}
