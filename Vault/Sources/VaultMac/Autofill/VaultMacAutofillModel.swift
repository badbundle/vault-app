import Foundation
import Observation
import VaultFeed
import VaultSettings

/// What opens the vault in the extension: `AutofillVaultService`, or a test's.
@MainActor
protocol VaultMacAutofillVaultUnlocking: AnyObject, AppLockPasswordService {
    var onNotEnoughMemory: (@MainActor () -> Void)? { get set }
    func hasMemoryHeadroomToUnlock() async throws -> Bool
}

extension AutofillVaultService: VaultMacAutofillVaultUnlocking {}

/// The AutoFill sheet's state, for one request: its own app lock, which starts locked and asks for Touch ID or the
/// Mac's password, then the App Lock Password (G25, G48), and the codes it can fill once that's open.
///
/// Its password attempts are counted with the app's, and it never makes the last one before the vault would be
/// erased: that one is only ever made at the app's lock screen (G20). It locks the vault again when the Mac locks
/// (G29), and at the end of the request.
@MainActor
@Observable
final class VaultMacAutofillModel {
    enum Availability: Equatable {
        /// Still finding out.
        case checking
        /// With Touch ID or the Mac's password, then the App Lock Password.
        case available
        /// The extension can't open the vault, so the user has to open Vault instead.
        case needsTheApp(NeedsTheAppReason)
    }

    enum NeedsTheAppReason: Equatable {
        /// Vault hasn't been set up on this Mac yet: its first launch sets the App Lock Password.
        case notSetUp
        /// Opening the vault would take more memory than the extension has.
        case notEnoughMemory
        /// The vault's being converted or erased, or its state can't be read.
        case unavailable
    }

    let appLock: AppLockService
    let dataModel: VaultDataModel
    private(set) var availability: Availability = .checking

    private let vaultService: any VaultMacAutofillVaultUnlocking
    private let accessMode: @Sendable () -> VaultAccessMode
    /// The last operation on the vault: they run one at a time, so a lock is never overtaken by an open.
    private var lastVaultOperation: Task<Void, Never>?

    init(
        dataModel: VaultDataModel,
        vaultService: any VaultMacAutofillVaultUnlocking,
        accessMode: @escaping @Sendable () -> VaultAccessMode,
        appLockSettings: AppLockSettingsStore,
        authentication: DeviceAuthenticationService,
    ) {
        let didLock = VaultMacAutofillLockHandler()
        self.dataModel = dataModel
        self.vaultService = vaultService
        self.accessMode = accessMode
        appLock = AppLockService(
            settings: appLockSettings,
            authenticationService: authentication,
            passwordService: vaultService,
            delay: .immediately,
            purgeSensitiveData: { didLock.handle() },
        )
        didLock.handler = { [weak self] in
            self?.lockTheVault()
        }
        self.vaultService.onNotEnoughMemory = { [weak self] in
            self?.availability = .needsTheApp(.notEnoughMemory)
        }
    }

    /// Gets the sheet ready to unlock, before it asks for anything: whatever an earlier request opened in this
    /// process is locked first. On the Mac the vault only opens with the App Lock Password, so until the app has set
    /// it, the sheet sends the user to Vault.
    func prepareToUnlock() async {
        await lockTheVault().value
        switch accessMode() {
        case .password:
            let hasHeadroom = (try? await vaultService.hasMemoryHeadroomToUnlock()) ?? false
            availability = hasHeadroom ? .available : .needsTheApp(.notEnoughMemory)
        case .plain, .deviceKey:
            availability = .needsTheApp(.notSetUp)
        case .unavailable:
            availability = .needsTheApp(.unavailable)
        }
    }

    /// Reads the codes, once the App Lock Password has opened the vault. The search never checks killphrases or
    /// finds hidden items: their keys are never loaded here (G2, G47).
    func loadCodes() async {
        guard !appLock.isLocked, accessMode() == .password else { return }
        await dataModel.reloadItems()
    }

    /// The codes the sheet offers: never a locked one, which would need Touch ID or the Mac's password to copy, nor a
    /// hidden one (G47).
    var codes: [VaultItem] {
        dataModel.items.filter { item in
            item.item.otpCode != nil && !item.metadata.lockState.isLocked
                && VaultItemViewConfiguration(
                    visibility: item.metadata.visibility,
                    searchableLevel: item.metadata.searchableLevel,
                ) == .alwaysVisible
        }
    }

    /// The Mac's locking, or going to sleep: the sheet's lock and the vault lock, and the codes go.
    func deviceWillLock() {
        appLock.deviceWillLock()
    }

    /// Locks the vault again at the end of the request, before the sheet goes.
    func endRequest() async {
        appLock.lockNow()
        await lockTheVault().value
    }

    @discardableResult
    private func lockTheVault() -> Task<Void, Never> {
        let previous = lastVaultOperation
        let operation = Task { [vaultService, dataModel] in
            await previous?.value
            await vaultService.lockVault()
            await dataModel.purgeVaultContents()
        }
        lastVaultOperation = operation
        return operation
    }
}

/// Calls whatever's set as the app lock locks, set once the model it belongs to is made.
@MainActor
private final class VaultMacAutofillLockHandler {
    var handler: (@MainActor () -> Void)?

    func handle() {
        handler?()
    }
}
