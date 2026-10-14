import ColorsipCore
import SwiftUI

struct PermissionGuideActions {
    var openSettings: @MainActor (Permission) -> Void
    var skip: @MainActor () -> Void
    var relaunch: @MainActor () -> Void
    var done: @MainActor () -> Void
}

/// The onboarding guide (`spec.md` §9): one missing permission at a time, then "all set".
struct PermissionGuideView: View {
    let permissions: Permissions
    let actions: PermissionGuideActions

    var body: some View {
        Group {
            if let guide = permissions.guide {
                switch guide.step {
                case .permission(let permission): step(permission, guide: guide)
                case .done: allSet
                }
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func step(_ permission: Permission, guide: PermissionGuide) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if guide.total > 1 {
                Text("Step \(guide.stepNumber) of \(guide.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: permission.systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 8) {
                    Text(permission.title).font(.title2.bold())
                    Text(permission.explanation)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Click Open System Settings, then turn on Colorsip in the list.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for permission…").foregroundStyle(.secondary)
            }
            if permission == .screenRecording {
                Text("If Colorsip doesn't move on after you turn it on, macOS needs it to restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if permission.isSkippable {
                    Button("Skip") { actions.skip() }
                }
                if permission == .screenRecording {
                    Button("Quit & Reopen") { actions.relaunch() }
                }
                Spacer()
                Button("Open System Settings") { actions.openSettings(permission) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        // A new step is a new view, so the focus moves to its default button.
        .id(permission)
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
