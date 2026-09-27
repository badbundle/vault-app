import Foundation
import FoundationExtensions
import Testing
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

/// How the AutoFill extension opens the encrypted vault, with the password kept in memory. It counts how often the
/// vault is locked and opened with the device key, and can be told whether there's the memory to open it.
@MainActor
final class FakeAutofillVaultService: AutofillVaultUnlocking {
    enum Headroom {
        case enough
        case notEnough
        /// The check never answers, as if it's still reading the file.
        case neverAnswers
        /// Each check waits for `answerHeadroomChecks(_:)`.
        case answersWhenTold
    }

    struct DeviceKeyFailure: Error {}

    var onNotEnoughMemory: (@MainActor () -> Void)?
    private(set) var lockCount = 0
    private(set) var deviceKeyOpenCount = 0
    /// Every lock and open, in order.
    private(set) var log = [String]()
    var failsToOpenWithDeviceKey = false
    /// Runs while the vault's being opened with the device key, once it's open.
    var whileOpening: (() -> Void)?
    private let base: FakeAppLockPasswordService
    private let headroom: Headroom
    private var waitingHeadroomChecks = [CheckedContinuation<Bool, Never>]()

    init(password: String = "correct horse", headroom: Headroom = .enough) {
        base = FakeAppLockPasswordService(password: password)
        self.headroom = headroom
    }

    var isPasswordSet: Bool {
        base.isPasswordSet
    }

    var erasesAfterFailedPasswords: Bool {
        base.erasesAfterFailedPasswords
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
        case .answersWhenTold:
            return await withCheckedContinuation { waitingHeadroomChecks.append($0) }
        }
    }

    /// Waits until a headroom check is waiting for an answer.
    func waitForHeadroomCheck() async throws {
        for _ in 0 ..< 1000 where waitingHeadroomChecks.isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(!waitingHeadroomChecks.isEmpty)
    }

    func answerHeadroomChecks(_ answer: Bool) {
        let waiting = waitingHeadroomChecks
        waitingHeadroomChecks.removeAll()
        for check in waiting {
            check.resume(returning: answer)
        }
    }

    func openWithDeviceKey() async throws {
        guard try await hasMemoryHeadroomToUnlock() else {
            onNotEnoughMemory?()
            throw AutofillVaultService.NotEnoughMemoryError()
        }
        guard !failsToOpenWithDeviceKey else { throw DeviceKeyFailure() }
        deviceKeyOpenCount += 1
        log.append("open with the device key")
        whileOpening?()
    }

    func lockVault() async {
        lockCount += 1
        log.append("lock")
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

    func setErasesAfterFailedPasswords(_ erases: Bool, current: String) async throws -> AppLockPasswordResult {
        try await base.setErasesAfterFailedPasswords(erases, current: current)
    }
}
