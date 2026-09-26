import Foundation

/// A backup that's running right now: what started it, when, and how far it has got.
public struct AutoBackupRun: Equatable, Sendable {
    /// What started a backup.
    public enum Trigger: Equatable, Sendable {
        /// Auto-backup started it by itself: the vault changed, or auto-backup was just turned on or
        /// given a folder.
        case automatic
        /// The user asked for it with "Back Up Now".
        case manual
    }

    public var trigger: Trigger
    public var startedAt: Date
    public var progress: AutoBackupProgress

    public init(trigger: Trigger, startedAt: Date, progress: AutoBackupProgress = .starting) {
        self.trigger = trigger
        self.startedAt = startedAt
        self.progress = progress
    }

    /// The same run, further along.
    public func with(progress: AutoBackupProgress) -> AutoBackupRun {
        var run = self
        run.progress = progress
        return run
    }
}
