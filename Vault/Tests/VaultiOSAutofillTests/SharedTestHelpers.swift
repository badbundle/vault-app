import Foundation
import FoundationExtensions
import VaultFeed
@testable import VaultiOSAutofill

func anyVaultItemMetadata(
    lockState: VaultItemLockState = .notLocked,
) -> VaultItem.Metadata {
    .init(
        id: Identifier<VaultItem>(),
        created: Date(),
        updated: Date(),
        relativeOrder: .min,
        userDescription: "any",
        tags: [],
        visibility: .always,
        searchableLevel: .full,
        searchPassphrase: nil,
        killphrase: nil,
        lockState: lockState,
        color: .black,
        showInQuickType: true,
        previewMode: .titleAndFirstLine,
    )
}

func anyVaultItem() -> VaultItem {
    VaultItem(
        metadata: anyVaultItemMetadata(),
        item: .secureNote(.init(title: "hello", contents: "hello", format: .markdown)),
    )
}

/// No-op key store for autofill snapshot tests that don't exercise the
/// killphrase digest path. Returns a fixed all-zero key so `loadOrCreate`
/// never fatal-errors when called from VaultDataModel.setup().
struct StubKillphraseKeyStore: KillphraseKeyStore {
    func loadOrCreate() async throws -> KeyData<32> {
        .zero()
    }
}

/// No-op key store for autofill snapshot tests that don't exercise the
/// search-passphrase digest path.
struct StubSearchPassphraseKeyStore: SearchPassphraseKeyStore {
    func loadOrCreate() async throws -> KeyData<32> {
        .zero()
    }
}

/// The AutoFill extension's App Lock Password, with the password kept in memory, that counts how often the vault is
/// locked and can be told whether there's the memory to unlock.
@MainActor
final class FakeAutofillPasswordService: AutofillPasswordUnlocking {
    enum Headroom {
        case enough
        case notEnough
        /// The check never answers, as if it's still reading the file.
        case neverAnswers
    }

    var onNotEnoughMemory: (@MainActor () -> Void)?
    private(set) var lockCount = 0
    private let base: FakeAppLockPasswordService
    private let headroom: Headroom

    init(password: String = "correct horse", headroom: Headroom = .enough) {
        base = FakeAppLockPasswordService(password: password)
        self.headroom = headroom
    }

    var isPasswordSet: Bool {
        base.isPasswordSet
    }

    func hasMemoryHeadroomToUnlock() async throws -> Bool {
        switch headroom {
        case .enough:
            return true
        case .notEnough:
            return false
        case .neverAnswers:
            try await Task.sleep(for: .seconds(60 * 60))
            return false
        }
    }

    func lockVault() async {
        lockCount += 1
    }

    /// Finds, as an unlock or a save would, that there isn't the memory.
    func runOutOfMemory() {
        onNotEnoughMemory?()
    }

    func remainingDelay() async throws -> Duration {
        try await base.remainingDelay()
    }

    func unlock(password: String) async throws -> AppLockPasswordResult {
        try await base.unlock(password: password)
    }

    func setPassword(_ password: String) async throws {
        try await base.setPassword(password)
    }

    func changePassword(current: String, new: String) async throws -> AppLockPasswordResult {
        try await base.changePassword(current: current, new: new)
    }

    func turnOffPassword(current: String) async throws -> AppLockPasswordResult {
        try await base.turnOffPassword(current: current)
    }

    func makeDuressVault(password: String) async throws {
        try await base.makeDuressVault(password: password)
    }
}
