import Foundation

/// Tracks whether a freshly created PDF backup has been saved anywhere.
///
/// Creating the PDF only writes a temporary file, so it isn't a backup until the user saves, prints or
/// sends it. The backup is logged only then, so the Backups screen never reports a backup that was
/// thrown away.
@MainActor
@Observable
public final class BackupGeneratedPDFViewModel {
    public let pdf: BackupCreatePDFViewModel.GeneratedPDF
    /// True once the user has finished saving, printing or sending the PDF at least once.
    public private(set) var isSaved = false

    private let backupEventLogger: any BackupEventLogger

    public init(pdf: BackupCreatePDFViewModel.GeneratedPDF, backupEventLogger: any BackupEventLogger) {
        self.pdf = pdf
        self.backupEventLogger = backupEventLogger
    }

    /// Call when the share sheet closes.
    ///
    /// - Parameter completed: Whether the user finished an action, such as saving to Files or printing,
    ///   rather than closing the sheet without doing anything.
    public func shareSheetFinished(completed: Bool) {
        guard completed, !isSaved else { return }
        isSaved = true
        backupEventLogger.exportedToPDF(date: pdf.createdDate, hash: pdf.dataHash)
    }
}
