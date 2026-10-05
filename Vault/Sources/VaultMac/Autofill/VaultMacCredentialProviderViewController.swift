import AppKit
import AuthenticationServices
import SwiftUI
import VaultFeed

/// The Mac's AutoFill extension: fills one-time codes into Safari and other apps, under the iOS AutoFill rules
/// (docs/mac-app.md, "QuickType and AutoFill"). It offers nothing without the sheet: the App Lock Password is always
/// on, so the system's identity store is kept empty (G46) and every request needs the user.
///
/// The extension's own target subclasses it, as the iOS extension's does.
open class VaultMacCredentialProviderViewController: ASCredentialProviderViewController {
    private let root = VaultMacAutofillRoot.shared
    private lazy var model = VaultMacAutofillModel(
        dataModel: root.dataModel,
        vaultService: root.vaultService,
        accessMode: { VaultMacAutofillRoot.accessMode() },
        appLockSettings: root.appLockSettings,
        authentication: root.authentication,
    )
    private var lockObservers: [(NotificationCenter, any NSObjectProtocol)] = []

    override open func loadView() {
        view = NSHostingView(rootView: VaultMacAutofillView(
            model: model,
            previews: root.previews,
            fill: { [weak self] code in self?.fill(code) },
            cancel: { [weak self] in self?.cancel() },
        ))
    }

    override open func viewWillAppear() {
        super.viewWillAppear()
        lockWhenTheMacLocks()
    }

    override open func viewDidAppear() {
        super.viewDidAppear()
        // Hide While Recording keeps the sheet out of every capture, as it does the app's windows (G24, G91).
        view.window?.sharingType = root.localSettings.state.hidesVaultWhileScreenCaptured ? .none : .readOnly
    }

    override open func viewDidDisappear() {
        super.viewDidDisappear()
        stopLockingWhenTheMacLocks()
        Task { await model.endRequest() }
    }

    // MARK: - Requests

    override open func prepareOneTimeCodeCredentialList(for _: [ASCredentialServiceIdentifier]) {
        // The sheet lists every code it can fill, with a search, as iOS AutoFill does.
    }

    override open func prepareInterfaceToProvideCredential(for _: any ASCredentialRequest) {
        // As above: the user picks the code.
    }

    override open func provideCredentialWithoutUserInteraction(for _: any ASCredentialRequest) {
        // The vault only opens with the App Lock Password, which needs the sheet.
        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
    }

    override open func prepareCredentialList(for _: [ASCredentialServiceIdentifier]) {
        // Vault fills one-time codes only, not passwords.
        extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
    }

    private func fill(_ code: String) {
        Task {
            await model.endRequest()
            await extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code))
        }
    }

    private func cancel() {
        Task {
            await model.endRequest()
            extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
        }
    }

    // MARK: - Locking

    /// Locks the sheet and the vault when the screen locks, the screen saver starts, or the Mac or its displays
    /// sleep, as the app does (G29, G86).
    private func lockWhenTheMacLocks() {
        guard lockObservers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        for name in VaultMacLockTriggers.lockingDistributedNotifications {
            lockObservers.append((distributed, distributed.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.model.deviceWillLock() }
            }))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in VaultMacLockTriggers.lockingWorkspaceNotifications {
            lockObservers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.model.deviceWillLock() }
            }))
        }
    }

    private func stopLockingWhenTheMacLocks() {
        for (center, observer) in lockObservers {
            center.removeObserver(observer)
        }
        lockObservers = []
    }
}
