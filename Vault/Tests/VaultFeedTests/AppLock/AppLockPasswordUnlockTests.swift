import Foundation
import FoundationExtensions
import LocalAuthentication
import TestHelpers
import Testing
@testable import VaultFeed

/// Unlocking a real vault with the App Lock Password, through a lock made as the app makes it at launch: on a device
/// with no passcode, and switching between the vault and its duress vault.
@MainActor
struct AppLockPasswordUnlockTests {
    private typealias SUT = EncryptedVaultPasswordServiceTests.SUT
    private static let password = "correct horse"
    private static let duressPassword = "plausible decoy"

    /// How a device says it has no passcode: by being unable to authenticate at all, or by failing the prompt.
    enum NoPasscode: CaseIterable {
        case cannotAuthenticate
        case passcodeNotSet
    }

    /// Without a device passcode, the lock stops at device authentication, as unavailable, and never asks for the
    /// password: a password tried anyway isn't counted, and opens nothing (VAULT-61). With a passcode set up again,
    /// the password opens the vault.
    @Test(arguments: NoPasscode.allCases)
    func noPasscode_withThePasswordSet_neverAsksForIt(noPasscode: NoPasscode) async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory)
            let item = try await sut.insertItem()
            #expect(try await sut.appLock.setPassword(Self.password))
            try await sut.lock()
            let policy = DeviceAuthenticationPolicyMock(
                canAuthenicateWithPasscode: noPasscode == .passcodeNotSet,
                canAuthenticateWithBiometrics: false,
            )
            policy.authenticateWithPasscodeHandler = { _ in throw LAError(.passcodeNotSet) }
            let appLock = sut.makeAppLock(authentication: policy)

            await appLock.unlock()
            await appLock.unlock(password: Self.password)

            #expect(appLock.state == .locked(.init(step: .deviceAuthentication, failure: .unavailable)))
            #expect(await sut.session.isLocked)
            #expect(try sut.attemptStorage.load() == nil)

            policy.canAuthenicateWithPasscode = true
            policy.authenticateWithPasscodeHandler = { _ in true }
            await appLock.unlock()
            #expect(appLock.state == .locked(.init(step: .password)))
            await appLock.unlock(password: Self.password)
            #expect(appLock.state == .unlocked)
            #expect(try await sut.itemIDs() == [item])
        }
    }

    /// Opening one vault after the other leaves nothing of the first in what the app shows: not its items, its tags
    /// or the search typed in it. The real vault after the duress one, and the other way round.
    @Test(arguments: [true, false])
    func switchingVaults_leavesNothingOfTheOtherVault(duressVaultFirst: Bool) async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory)
            let realItem = try await sut.insertItem()
            let realTag = try await sut.session.insertTag(item: .init(
                name: "Real",
                color: .tagDefault,
                iconName: VaultItemTag.defaultIconName,
            ))
            #expect(try await sut.appLock.setPassword(Self.password))
            #expect(try await sut.appLock.makeDuressVault(password: Self.duressPassword))
            try await sut.unlockAgain(with: Self.duressPassword)
            let duressItem = try await sut.insertItem()
            let duressTag = try await sut.session.insertTag(item: .init(
                name: "Duress",
                color: .tagDefault,
                iconName: VaultItemTag.defaultIconName,
            ))
            try await sut.lock()
            let dataModel = Self.makeDataModel(session: sut.session)
            let purges = PurgeTasks()
            let appLock = sut.makeAppLock {
                purges.purgeAsTheAppDoes(dataModel)
            }
            let real = (password: Self.password, item: realItem, tag: realTag)
            let duress = (password: Self.duressPassword, item: duressItem, tag: duressTag)
            let (first, second) = duressVaultFirst ? (duress, real) : (real, duress)

            await appLock.unlock()
            await appLock.unlock(password: first.password)
            await dataModel.reloadData()
            dataModel.itemsSearchQuery = "a search in the first vault"
            #expect(dataModel.items.map(\.id) == [first.item])
            #expect(dataModel.allTags.map(\.id) == [first.tag])

            appLock.scenePhaseDidChange(to: .background)
            await appLock.vaultLock?.value
            await purges.finish()
            #expect(dataModel.items.isEmpty)
            #expect(dataModel.allTags.isEmpty)
            #expect(dataModel.itemsSearchQuery.isEmpty)

            await appLock.unlock()
            await appLock.unlock(password: second.password)
            #expect(appLock.state == .unlocked)
            await dataModel.reloadData()
            #expect(dataModel.items.map(\.id) == [second.item])
            #expect(dataModel.allTags.map(\.id) == [second.tag])
            #expect(dataModel.itemsSearchQuery.isEmpty)
        }
    }
}

// MARK: - Helpers

extension AppLockPasswordUnlockTests {
    /// What the app shows the vault with.
    private static func makeDataModel(session: VaultStoreSession) -> VaultDataModel {
        VaultDataModel(
            vaultStore: session,
            vaultTagStore: session,
            vaultImporter: session,
            vaultDeleter: session,
            vaultKillphraseDeleter: session,
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: StubKillphraseKeyStore(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        )
    }

    /// Purges the data model as the app does when it locks (`VaultRoot.purgeSensitiveDataForAppLock()`), keeping the
    /// tasks for the test to wait for.
    @MainActor
    private final class PurgeTasks {
        private var tasks = [Task<Void, Never>]()

        func purgeAsTheAppDoes(_ dataModel: VaultDataModel) {
            dataModel.purgeSensitiveData()
            tasks.append(Task {
                await dataModel.purgeVaultContents()
            })
        }

        func finish() async {
            for task in tasks {
                await task.value
            }
        }
    }
}

extension EncryptedVaultPasswordServiceTests.SUT {
    /// Another lock over the same vault, as the app makes it at launch: it starts locked while the password is set.
    /// With its own device authentication, and what it purges as it locks.
    func makeAppLock(
        authentication: any DeviceAuthenticationPolicy = .alwaysAllow,
        purgeSensitiveData: @escaping @MainActor () -> Void = {},
    ) -> AppLockService {
        AppLockService(
            settings: keychain.settings,
            authenticationService: DeviceAuthenticationService(policy: authentication),
            passwordService: service,
            clock: keychain.attemptClock,
            purgeSensitiveData: purgeSensitiveData,
        )
    }
}
