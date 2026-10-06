import SwiftUI
import VaultFeed

/// Shows a window's content only while Vault is unlocked. Until then, the window says Vault is locked, and offers to
/// bring the main window forward to unlock it: a window other than the main one shows nothing of the vault while it's
/// locked, nor before the App Lock Password is set.
struct VaultMacLockedWindowGate<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @State private var appLock = VaultMacRoot.appLockService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if appLock.isPasswordSet, !appLock.isLocked {
            content()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Vault Is Locked")
                    .font(.headline)
                Button("Unlock Vault…") {
                    openWindow(id: VaultMacWindow.main.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("locked-window")
        }
    }
}
