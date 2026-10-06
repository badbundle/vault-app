import AppKit
import AuthenticationServices
import SwiftUI
import VaultFeed
import VaultSettings

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
    private var lockObserver: VaultMacAutofillLockObserver?

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
        keepOutOfCaptures()
        lockWhenTheMacLocksOrTheUserLeaves()
        // Nothing is ever offered without the sheet (G46): the system's list of codes stays empty.
        Task { try? await ASCredentialIdentityStore.shared.removeAllCredentialIdentities() }
    }

    override open func viewDidAppear() {
        super.viewDidAppear()
        keepOutOfCaptures()
    }

    override open func viewDidDisappear() {
        super.viewDidDisappear()
        lockObserver?.stop()
        lockObserver = nil
        Task { await model.endRequest() }
    }

    /// Hide While Recording keeps the sheet out of every capture, as it does the app's windows (G24, G91), as macOS
    /// shows it. The setting's read afresh for each request, as the app can change it meanwhile.
    private func keepOutOfCaptures() {
        let settings = LocalSettings(defaults: root.sharedDefaults, sharedDefaults: root.sharedDefaults)
        view.window?.sharingType = settings.state.hidesVaultWhileScreenCaptured ? .none : .readOnly
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

    /// Locks the sheet and the vault when the Mac locks or sleeps (G29, G86), and when the user goes to another app,
    /// as the app locks when another comes to the front (G22).
    private func lockWhenTheMacLocksOrTheUserLeaves() {
        guard lockObserver == nil else { return }
        lockObserver = VaultMacAutofillLockObserver(
            hostProcess: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            macWillLock: { [weak self] in self?.model.deviceWillLock() },
            userDidLeave: { [weak self] in self?.model.userDidLeave() },
        )
    }
}
