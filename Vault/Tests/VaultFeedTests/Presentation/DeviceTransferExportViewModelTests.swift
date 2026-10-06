import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

@MainActor
struct DeviceTransferExportViewModelTests {
    @Test
    func init_hasNoSideEffects() throws {
        let vaultStore = VaultStoreStub()
        let vaultTagStore = VaultTagStoreStub()
        let backupPasswordStore = BackupPasswordStoreMock()
        _ = try makeSUT(vaultStore: vaultStore, vaultTagStore: vaultTagStore, backupPasswordStore: backupPasswordStore)

        #expect(vaultStore.calledMethods == [])
        #expect(vaultTagStore.calledMethods == [])
        #expect(backupPasswordStore.fetchPasswordCallCount == 0)
        #expect(backupPasswordStore.setCallCount == 0)
    }

    @Test
    func init_initialStateIsIdle() throws {
        let sut = try makeSUT()

        #expect(sut.state == .idle)
    }

    @Test
    func generateShards_transitionsToGeneratingState() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let sut = try makeSUT(vaultStore: vaultStore)

        await sut.generateShards()

        // Should transition from generating to displayingQR
        #expect(sut.state.isDisplaying)
    }

    @Test
    func generateShards_createsShards() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let sut = try makeSUT(vaultStore: vaultStore)

        await sut.generateShards()

        if case let .displayingQR(_, totalCount) = sut.state {
            #expect(totalCount > 0)
        } else {
            Issue.record("Expected displayingQR state")
        }
    }

    @Test
    func generateShards_startsAtFirstCode() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let sut = try makeSUT(vaultStore: vaultStore)

        await sut.generateShards()

        if case let .displayingQR(currentIndex, _) = sut.state {
            #expect(currentIndex == 0)
        } else {
            Issue.record("Expected displayingQR state")
        }
    }

    @Test
    func generateShards_rendersQRCode() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let sut = try makeSUT(vaultStore: vaultStore)

        await sut.generateShards()

        #expect(sut.currentQRCodeImage != nil)
    }

    /// A transfer saves nothing, so it isn't a backup: the last backup stays what it was.
    @Test
    func generateShards_isNotLoggedAsABackup() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let logger = try BackupEventLoggerImpl(
            defaults: .init(userDefaults: testUserDefaults()),
            clock: EpochClockMock(currentTime: 100),
        )
        let sut = try makeSUT(vaultStore: vaultStore, backupEventLogger: logger)

        await sut.generateShards()

        #expect(sut.state.isDisplaying)
        #expect(logger.lastBackupEvent() == nil)
    }

    @Test
    func generateShards_errorSetsErrorState() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in throw TestError() }
        let sut = try makeSUT(vaultStore: vaultStore)

        await sut.generateShards()

        #expect(sut.state.isError)
    }

    @Test
    func autoCycling_advancesThroughCodes() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let timer = IntervalTimerMock()
        let sut = try makeSUT(vaultStore: vaultStore, intervalTimer: timer)

        await sut.generateShards()

        // Verify we start at index 0
        if case let .displayingQR(currentIndex, _) = sut.state {
            #expect(currentIndex == 0)
        }

        // Advance the timer
        try await timer.finishTimer(at: 0)
        await waitForDisplayingIndex(1, in: sut)

        // Should advance to index 1
        if case let .displayingQR(currentIndex, _) = sut.state {
            #expect(currentIndex == 1)
        } else {
            Issue.record("Expected displayingQR state after advancing")
        }
    }

    @Test
    func stop_endsTheTransferAndForgetsItsCodes() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let timer = IntervalTimerMock()
        let sut = try makeSUT(vaultStore: vaultStore, intervalTimer: timer)
        await sut.generateShards()
        #expect(sut.state.isDisplaying)

        sut.stop()

        #expect(sut.state == .idle)
        #expect(sut.currentQRCodeImage == nil)
        // The cycle has ended, so a timer firing changes nothing.
        try? await timer.finishTimer(at: 0)
        #expect(sut.state == .idle)
    }

    @Test
    func autoCycling_wrapsAroundAtEnd() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let timer = IntervalTimerMock()
        let sut = try makeSUT(vaultStore: vaultStore, intervalTimer: timer)

        await sut.generateShards()

        // Get total count
        guard case let .displayingQR(_, totalCount) = sut.state else {
            Issue.record("Expected displayingQR state")
            return
        }

        // Advance through all codes and wrap around
        // Each finishTimer call needs the correct index since a new timer is created each time
        for i in 0 ..< totalCount {
            try await timer.finishTimer(at: i)
            await waitForDisplayingIndex((i + 1) % totalCount, in: sut)
        }

        // Should wrap back to index 0
        if case let .displayingQR(currentIndex, _) = sut.state {
            #expect(currentIndex == 0)
        } else {
            Issue.record("Expected to wrap around to index 0")
        }
    }

    @Test
    func autoCycling_updatesQRCodeImage() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "", items: [], tags: [])
        }
        let timer = IntervalTimerMock()
        let sut = try makeSUT(vaultStore: vaultStore, intervalTimer: timer)

        await sut.generateShards()

        let initialImageData = sut.currentQRCodeImage?.pngData()

        // Advance the timer
        try await timer.finishTimer(at: 0)
        await waitForDisplayingIndex(1, in: sut)

        let updatedImageData = sut.currentQRCodeImage?.pngData()

        #expect(initialImageData != nil)
        #expect(updatedImageData != nil)
        #expect(initialImageData != updatedImageData)
    }
}

// MARK: - Helpers

extension DeviceTransferExportViewModelTests {
    @MainActor
    private func makeSUT(
        vaultStore: any VaultStore = VaultStoreStub(),
        vaultTagStore: any VaultTagStore = VaultTagStoreStub(),
        backupPasswordStore: any BackupPasswordStore = BackupPasswordStoreMock(),
        backupPassword: DerivedEncryptionKey = anyBackupPassword(),
        clock: some EpochClock = EpochClockMock(currentTime: 100),
        backupEventLogger: any BackupEventLogger = BackupEventLoggerMock(),
        intervalTimer: any IntervalTimer = IntervalTimerMock(),
    ) throws -> DeviceTransferExportViewModel {
        DeviceTransferExportViewModel(
            backupPassword: backupPassword,
            dataModel: VaultDataModel(
                vaultStore: vaultStore,
                vaultTagStore: vaultTagStore,
                vaultImporter: VaultStoreImporterMock(),
                vaultDeleter: VaultStoreDeleterMock(),
                vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
                vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
                backupPasswordStore: backupPasswordStore,
                killphraseKeyStore: StubKillphraseKeyStore(),
                killphraseRehashService: nil,
                searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
                searchPassphraseRehashService: nil,
                backupEventLogger: backupEventLogger,
            ),
            clock: clock,
            intervalTimer: intervalTimer,
        )
    }

    private func waitForDisplayingIndex(_ expectedIndex: Int, in sut: DeviceTransferExportViewModel) async {
        for _ in 0 ..< 100 {
            if case let .displayingQR(currentIndex, _) = sut.state, currentIndex == expectedIndex {
                return
            }
            await Task.yield()
        }
        Issue.record("Expected displayingQR index \(expectedIndex), got \(sut.state)")
    }
}
