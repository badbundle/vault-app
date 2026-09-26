import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

@MainActor
struct SetAsideVaultsViewModelTests {
    @Test
    func init_loadsSetAsideVaults() {
        let archives = VaultStoreArchivingMock()
        archives.archivesHandler = { [anyArchive()] }

        let sut = makeSUT(archives: archives)

        #expect(sut.archives == [anyArchive()])
        #expect(archives.deleteAllCallCount == 0)
    }

    @Test
    func summary_isNilWithoutSetAsideVaults() {
        let archives = VaultStoreArchivingMock()
        archives.archivesHandler = { [] }

        let sut = makeSUT(archives: archives)

        #expect(sut.summary == nil)
    }

    @Test
    func summary_saysWhenTheVaultWasSetAside() throws {
        let archives = VaultStoreArchivingMock()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        archives.archivesHandler = { [anyArchive(date: date)] }

        let sut = makeSUT(archives: archives)

        let summary = try #require(sut.summary)
        #expect(summary.contains(date.formatted(date: .abbreviated, time: .omitted)))
        #expect(summary.contains("couldn't be opened on"))
    }

    @Test
    func summary_countsSetAsideVaultsAndGivesTheLatest() throws {
        let archives = VaultStoreArchivingMock()
        let latest = Date(timeIntervalSince1970: 1_700_000_000)
        archives.archivesHandler = { [
            anyArchive(date: Date(timeIntervalSince1970: 1_600_000_000)),
            anyArchive(date: latest),
        ] }

        let sut = makeSUT(archives: archives)

        let summary = try #require(sut.summary)
        #expect(summary.contains("2 times"))
        #expect(summary.contains(latest.formatted(date: .abbreviated, time: .omitted)))
    }

    @Test
    func deleteAll_deletesOnceAuthenticated() async {
        let archives = VaultStoreArchivingMock()
        archives.archivesHandler = { [anyArchive()] }
        archives.deleteAllHandler = { archives.archivesHandler = { [] } }
        let sut = makeSUT(archives: archives, policy: .alwaysAllow)

        await sut.deleteAll()

        #expect(archives.deleteAllCallCount == 1)
        #expect(sut.archives.isEmpty)
        #expect(sut.summary == nil)
        #expect(sut.deleteError == nil)
        #expect(sut.isDeleting == false)
    }

    @Test
    func deleteAll_deletesNothingWithoutAuthentication() async {
        let archives = VaultStoreArchivingMock()
        archives.archivesHandler = { [anyArchive()] }
        let sut = makeSUT(archives: archives, policy: .alwaysDeny)

        await sut.deleteAll()

        #expect(archives.deleteAllCallCount == 0)
        #expect(sut.archives == [anyArchive()])
        #expect(sut.deleteError != nil)
    }

    @Test
    func deleteAll_showsErrorIfDeletingFails() async {
        let archives = VaultStoreArchivingMock()
        archives.archivesHandler = { [anyArchive()] }
        archives.deleteAllHandler = { throw TestError() }
        let sut = makeSUT(archives: archives, policy: .alwaysAllow)

        await sut.deleteAll()

        #expect(sut.deleteError != nil)
        #expect(sut.archives == [anyArchive()])
    }

    @Test
    func deleteAll_doesNothingWithoutSetAsideVaults() async {
        let archives = VaultStoreArchivingMock()
        archives.archivesHandler = { [] }
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        let sut = makeSUT(archives: archives, policy: policy)

        await sut.deleteAll()

        #expect(archives.deleteAllCallCount == 0)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }
}

// MARK: - Helpers

extension SetAsideVaultsViewModelTests {
    private func makeSUT(
        archives: VaultStoreArchivingMock,
        policy: some DeviceAuthenticationPolicy = .alwaysAllow,
    ) -> SetAsideVaultsViewModel {
        SetAsideVaultsViewModel(
            archives: archives,
            authenticationService: DeviceAuthenticationService(policy: policy),
        )
    }
}

private func anyArchive(date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> VaultStoreArchive {
    VaultStoreArchive(
        url: URL(fileURLWithPath: "/tmp/vault-primary.failed-open-\(date.timeIntervalSince1970)"),
        date: date,
    )
}
