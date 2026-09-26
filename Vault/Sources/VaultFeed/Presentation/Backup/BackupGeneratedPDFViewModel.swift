import Foundation

/// Tracks whether a freshly created PDF backup has been saved anywhere.
///
/// Creating the PDF only makes it in memory, so it isn't a backup until the user saves, prints or sends it. The
/// backup is logged only then, so the Backups screen never reports a backup that was thrown away.
@MainActor
@Observable
public final class BackupGeneratedPDFViewModel {
    public let pdf: BackupCreatePDFViewModel.GeneratedPDF
    /// True once the user has finished saving, printing or sending the PDF at least once.
    public private(set) var isSaved = false
    /// The PDF's file while the share sheet has it, and `nil` otherwise. The share sheet shows while it's set.
    public private(set) var fileBeingShared: URL?
    /// Why the PDF couldn't be shared, if the last try failed.
    public private(set) var shareError: PresentationError?

    private let backupEventLogger: any BackupEventLogger
    private let files: BackupPDFTemporaryFiles

    public init(
        pdf: BackupCreatePDFViewModel.GeneratedPDF,
        backupEventLogger: any BackupEventLogger,
        files: BackupPDFTemporaryFiles,
    ) {
        self.pdf = pdf
        self.backupEventLogger = backupEventLogger
        self.files = files
    }

    /// Call when the user asks to save or print the PDF. Writes its file for the share sheet.
    public func share() {
        guard fileBeingShared == nil else { return }
        do {
            fileBeingShared = try files.write(pdf)
            shareError = nil
        } catch {
            shareError = PresentationError(
                userTitle: "Can't save the PDF",
                userDescription: "Unable to get your backup ready to save. Please try again.",
                debugDescription: error.localizedDescription,
            )
        }
    }

    /// Call when the share sheet closes. Deletes the PDF's file, whether or not it was saved.
    ///
    /// - Parameter completed: Whether the user finished an action, such as saving to Files or printing,
    ///   rather than closing the sheet without doing anything.
    public func shareSheetFinished(completed: Bool) {
        if let fileBeingShared {
            files.delete(fileBeingShared)
        }
        fileBeingShared = nil
        guard completed, !isSaved else { return }
        isSaved = true
        backupEventLogger.exportedToPDF(backupDate: pdf.createdDate, hash: pdf.dataHash)
    }
}
