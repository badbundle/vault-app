import Combine
import Foundation
import FoundationExtensions
import ImageTools
import VaultBackup
import VaultCore
import VaultExport
import VaultKeygen

@MainActor
@Observable
public final class DeviceTransferExportViewModel {
    public enum State: Equatable {
        case idle
        case generating
        case displayingQR(currentIndex: Int, totalCount: Int)
        case error(PresentationError)
        case completed

        public var isError: Bool {
            switch self {
            case .error: true
            default: false
            }
        }

        public var isDisplaying: Bool {
            switch self {
            case .displayingQR: true
            default: false
            }
        }
    }

    public private(set) var state: State = .idle
    public private(set) var currentQRCodeImage: PlatformImage?

    private var shards: [DataShard] = []
    private var cycleTask: Task<Void, Never>?
    /// Goes up each time the transfer stops, so a generation that was underway then shows nothing when it finishes.
    private var generation = 0

    private let backupPassword: DerivedEncryptionKey
    private let dataModel: VaultDataModel
    private let clock: any EpochClock
    private let intervalTimer: any IntervalTimer

    /// A transfer saves nothing, so it isn't logged as a backup: the Backups page and the App Lock Password's form go
    /// by the last backup that was saved somewhere.
    public init(
        backupPassword: DerivedEncryptionKey,
        dataModel: VaultDataModel,
        clock: any EpochClock,
        intervalTimer: any IntervalTimer,
    ) {
        self.backupPassword = backupPassword
        self.dataModel = dataModel
        self.clock = clock
        self.intervalTimer = intervalTimer
    }

    public func generateShards() async {
        generation += 1
        let generation = generation
        do {
            state = .generating

            // Export vault data
            let payload = try await dataModel.makeExport(userDescription: "")
            guard generation == self.generation else { return }

            let shards = try await makeShards(payload: payload)
            guard generation == self.generation else { return }
            var image: PlatformImage?
            if let first = shards.first {
                image = await Self.renderQRCode(of: first)
                guard generation == self.generation else { return }
            }

            // Start displaying first QR code
            self.shards = shards
            state = .displayingQR(currentIndex: 0, totalCount: shards.count)
            currentQRCodeImage = image
            startCycling()
        } catch {
            guard generation == self.generation else { return }
            state = .error(.init(
                userTitle: "Transfer Error",
                userDescription: "Failed to prepare data for transfer. Please try again.",
                debugDescription: error.localizedDescription,
            ))
        }
    }

    /// Ends the transfer: the codes stop cycling, and the encrypted vault they carried is forgotten. Generating again
    /// starts a new transfer.
    public func stop() {
        generation += 1
        cycleTask?.cancel()
        cycleTask = nil
        shards = []
        currentQRCodeImage = nil
        state = .idle
    }

    private func startCycling() {
        guard case .displayingQR = state else { return }
        cycleTask?.cancel()

        cycleTask = Task { [weak self, intervalTimer] in
            while !Task.isCancelled {
                do {
                    try await intervalTimer.wait(for: 2.0)
                    guard !Task.isCancelled, let self else { break }
                    await advanceToNextShard()
                } catch {
                    break
                }
            }
        }
    }

    private func advanceToNextShard() async {
        guard case let .displayingQR(currentIndex, totalCount) = state, currentIndex < shards.count else { return }
        let generation = generation

        let nextIndex = (currentIndex + 1) % totalCount
        let image = await Self.renderQRCode(of: shards[nextIndex])
        // Stopped, or started again, while it rendered.
        guard generation == self.generation else { return }
        state = .displayingQR(currentIndex: nextIndex, totalCount: totalCount)
        currentQRCodeImage = image
    }

    /// Encrypts the vault, encodes it and splits it into shards, off the main actor.
    private nonisolated func makeShards(payload: VaultApplicationPayload) async throws -> [DataShard] {
        // Nothing is saved, so a random amount of padding is enough, and the transfer stays quick.
        let backupExporter = EncryptedVaultEncoder(clock: clock, backupPassword: backupPassword, padding: .random)
        let encryptedVault = try backupExporter.encryptAndEncode(payload: payload)
        let vaultData = try EncryptedVaultCoder().encode(vault: encryptedVault)
        return DataShardBuilder().makeShards(from: vaultData)
    }

    /// Renders a shard's QR code off the main actor, where it would hold up the window each time the code changes.
    private nonisolated static func renderQRCode(of shard: DataShard) async -> sending PlatformImage? {
        guard let shardData = try? EncryptedVaultCoder().encode(shard: shard) else { return nil }
        return QRCodeImageRenderer().makeImage(fromData: shardData)
    }
}
