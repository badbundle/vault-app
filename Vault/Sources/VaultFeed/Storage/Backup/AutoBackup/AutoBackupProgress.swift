import Foundation

/// How far an in-flight backup has got.
///
/// Progress is reported per phase; `fractionCompleted` folds the phases into a single `0...1` value
/// weighted by how long each phase typically takes, so a bar driven by it moves at a steady pace.
public struct AutoBackupProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable, CaseIterable {
        /// Reading the vault out of storage.
        case exporting
        /// Encrypting the exported vault with the backup password.
        case encrypting
        /// Drawing the encrypted vault as QR codes into the PDF. Dominates the backup time.
        case rendering
        /// Writing the PDF to the storage provider.
        case saving

        public var localizedTitle: String {
            switch self {
            case .exporting: "Exporting vault…"
            case .encrypting: "Encrypting…"
            case .rendering: "Rendering QR codes…"
            case .saving: "Saving…"
            }
        }

        /// The slice of overall progress this phase occupies.
        var overallRange: ClosedRange<Double> {
            switch self {
            case .exporting: 0 ... 0.05
            case .encrypting: 0.05 ... 0.15
            case .rendering: 0.15 ... 0.95
            case .saving: 0.95 ... 1
            }
        }
    }

    public let phase: Phase
    /// Progress within `phase`, in `0...1`.
    public let phaseFraction: Double

    public init(phase: Phase, phaseFraction: Double = 0) {
        self.phase = phase
        self.phaseFraction = min(max(phaseFraction, 0), 1)
    }

    /// Overall progress in `0...1`.
    public var fractionCompleted: Double {
        let range = phase.overallRange
        return range.lowerBound + (range.upperBound - range.lowerBound) * phaseFraction
    }

    /// The state of a backup that has just begun.
    public static let starting = AutoBackupProgress(phase: .exporting)
}
