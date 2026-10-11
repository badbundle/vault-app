import Foundation
import FoundationExtensions
import VaultKeygen

/// Records the quality of service of the thread each derivation runs on, which the threads a derivation starts, such
/// as Argon2id's lanes, take on too, then derives as `VaultKeyDeriver.testing` does.
///
/// The thread's own quality of service, not how it's scheduled for now: awaiting work from a task of higher priority
/// can raise that for a while, so a derivation started at background priority would still show as background here.
final class QoSRecordingKeyDeriver: KeyDeriver {
    private let recorded = SharedMutex<[qos_class_t]>([])

    /// The quality of service of each derivation's thread, in turn.
    var qualitiesOfService: [qos_class_t] {
        recorded.value
    }

    func key(password: Data, salt: Data) throws -> KeyData<32> {
        recorded.modify { $0.append(qos_class_self()) }
        return try VaultKeyDeriver.testing.key(password: password, salt: salt)
    }

    var uniqueAlgorithmIdentifier: String {
        "qos-recording"
    }
}
