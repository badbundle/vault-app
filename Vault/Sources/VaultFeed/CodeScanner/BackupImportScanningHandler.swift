import Foundation
import FoundationExtensions
import VaultBackup

/// Scanning the individual codes in a vault backup, recreate the EncryptedVault payload.
@Observable
public final class BackupImportScanningHandler: CodeScanningHandler {
    private var shardDecoder = DataShardDecoder()
    public init() {}

    public struct State {
        public var totalNumberOfShards: Int
        public var collectedShardIndexes: Set<Int>
        public var remainingShardIndexes: Set<Int>
    }

    public var shardState: State? {
        if let state = shardDecoder.state {
            State(
                totalNumberOfShards: state.total,
                collectedShardIndexes: state.collectedIndexes,
                remainingShardIndexes: state.remainingIndexes,
            )
        } else {
            nil
        }
    }

    public var hasPartialState: Bool {
        shardState != nil
    }

    public func makeSimulatedHandler() -> some SimulatedCodeScanningHandler<EncryptedVault> {
        BackupImportScanningHandlerSimulated()
    }

    public func decode(data: String) -> CodeScanningResult<EncryptedVault> {
        let shardData = Data(data.utf8)
        do {
            try shardDecoder.add(shardData: shardData)
            if !shardDecoder.isReadyToDecode {
                return .continueScanning(.success)
            }
        } catch let error as DataShardDecoder.AddShardError where error.canIgnoreError {
            return .continueScanning(.ignore)
        } catch {
            return .continueScanning(.invalidCode)
        }

        do {
            let encryptedVault = try decodeEncryptedVault()
            return .endScanning(.dataRetrieved(encryptedVault))
        } catch {
            // We cannot recover if this fails because the state is tainted and we
            // have no idea what caused it.
            return .endScanning(.unrecoverableError)
        }
    }

    private func decodeEncryptedVault() throws -> EncryptedVault {
        let encryptedVaultData = try shardDecoder.decodeData()
        return try EncryptedVaultCoder().decode(vaultData: encryptedVaultData)
    }
}

public final class BackupImportScanningHandlerSimulated: SimulatedCodeScanningHandler {
    public init() {}

    public func decodeSimulated() -> CodeScanningResult<EncryptedVault> {
        .endScanning(.dataRetrieved(makeExampleEncryptedVault()))
    }

    private func makeExampleEncryptedVault() -> EncryptedVault {
        do {
            let application = VaultApplicationPayload(
                userDescription: "Hello",
                items: [.init(
                    metadata: .init(
                        id: .new(),
                        created: Date(),
                        updated: Date(),
                        relativeOrder: 0,
                        userDescription: "This is a test item",
                        tags: [],
                        visibility: .always,
                        searchableLevel: .full,
                        searchPassphrase: nil,
                        killphrase: nil,
                        lockState: .notLocked,
                        color: nil,
                        showInQuickType: false,
                        previewMode: .titleAndFirstLine,
                    ),
                    item: .secureNote(.init(
                        title: "My example secure note",
                        contents: "This is contents",
                        format: .markdown,
                    )),
                )],
                tags: [],
            )
            let derived = try VaultKeyDeriver.testing.createEncryptionKey(password: "hello")
            let encoder = EncryptedVaultEncoder(clock: EpochClockImpl(), backupPassword: derived)
            return try encoder.encryptAndEncode(payload: application)
        } catch {
            return EncryptedVault(
                version: "1.0.0",
                data: Data(),
                authentication: Data(),
                encryptionIV: Data(),
                keygenSalt: Data(),
                keygenSignature: VaultKeyDeriver.Signature.testing.rawValue,
            )
        }
    }
}
