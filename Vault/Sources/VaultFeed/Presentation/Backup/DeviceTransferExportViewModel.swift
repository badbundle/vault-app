import Combine
import Foundation
import FoundationExtensions
import ImageTools
import UIKit
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
    public private(set) var currentQRCodeImage: UIImage?

    private var shards: [DataShard] = []
    private var cycleTask: Task<Void, Never>?
    private var payloadHash: Digest<VaultApplicationPayload>.SHA256?

    private let backupPassword: DerivedEncryptionKey
    private let dataModel: VaultDataModel
    private let clock: any EpochClock
    private let backupEventLogger: any BackupEventLogger
    private let intervalTimer: any IntervalTimer

    public init(
        backupPassword: DerivedEncryptionKey,
        dataModel: VaultDataModel,
        clock: any EpochClock,
        backupEventLogger: any BackupEventLogger,
        intervalTimer: any IntervalTimer,
    ) {
        self.backupPassword = backupPassword
        self.dataModel = dataModel
        self.clock = clock
        self.backupEventLogger = backupEventLogger
        self.intervalTimer = intervalTimer
    }

    public func generateShards() async {
        do {
            state = .generating
            let currentDate = clock.currentDate

            // Export vault data
            let payload = try await dataModel.makeExport(userDescription: "")

            // Encrypt and encode
            let encryptedVault = try await encryptPayload(payload: payload)

            // Convert to data
            let coder = EncryptedVaultCoder()
            let vaultData = try coder.encode(vault: encryptedVault)

            // Split into shards
            let shardBuilder = DataShardBuilder()
            shards = shardBuilder.makeShards(from: vaultData)

            // Store hash for event logging
            let hash = try DigestHasher().sha256(value: payload)
            payloadHash = hash

            // Log export event
            backupEventLogger.exportedToDevice(backupDate: currentDate, hash: hash)

            // Start displaying first QR code
            state = .displayingQR(currentIndex: 0, totalCount: shards.count)
            renderCurrentQRCode()
            startCycling()
        } catch {
            state = .error(.init(
                userTitle: "Transfer Error",
                userDescription: "Failed to prepare data for transfer. Please try again.",
                debugDescription: error.localizedDescription,
            ))
        }
    }

    private func startCycling() {
        guard case .displayingQR = state else { return }
        cycleTask?.cancel()

        cycleTask = Task {
            while !Task.isCancelled {
                do {
                    try await intervalTimer.wait(for: 2.0)
                    guard !Task.isCancelled else { break }
                    advanceToNextShard()
                } catch {
                    break
                }
            }
        }
    }

    private func advanceToNextShard() {
        guard case let .displayingQR(currentIndex, totalCount) = state else { return }

        let nextIndex = (currentIndex + 1) % totalCount
        state = .displayingQR(currentIndex: nextIndex, totalCount: totalCount)
        renderCurrentQRCode()
    }

    private func renderCurrentQRCode() {
        guard case let .displayingQR(currentIndex, _) = state else { return }
        guard currentIndex < shards.count else { return }

        let shard = shards[currentIndex]

        do {
            let coder = EncryptedVaultCoder()
            let shardData = try coder.encode(shard: shard)
            let renderer = QRCodeImageRenderer()
            currentQRCodeImage = renderer.makeImage(fromData: shardData)
        } catch {
            currentQRCodeImage = nil
        }
    }

    private nonisolated func encryptPayload(payload: VaultApplicationPayload) async throws -> EncryptedVault {
        let backupExporter = EncryptedVaultEncoder(clock: clock, backupPassword: backupPassword)
        return try backupExporter.encryptAndEncode(payload: payload)
    }
}
