import SwiftUI

/// A page's message, when there's something to do before it can show more.
public struct VaultMacBackupNotice: View {
    var systemImage: String
    var title: String
    var message: String
    var action: (title: String, perform: () -> Void)?

    public init(
        systemImage: String,
        title: String,
        message: String,
        action: (title: String, perform: () -> Void)? = nil,
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let action {
                Button(action.title, action: action.perform)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("backups.notice-action")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
