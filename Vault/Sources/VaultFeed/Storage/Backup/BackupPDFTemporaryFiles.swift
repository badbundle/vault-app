import Foundation
import PDFKit

/// The temporary files a PDF backup is shared from.
///
/// A backup PDF is the whole vault as it was when the PDF was made, encrypted, including items deleted since (by a
/// killphrase, say). So its file only exists while the share sheet has it: it's written when the sheet opens and
/// deleted when the sheet closes, whether or not the backup was saved. Any left behind, because the app was closed
/// with the sheet open or by earlier versions of the app, are deleted the next time the Backups page opens.
public struct BackupPDFTemporaryFiles {
    public enum Error: Swift.Error, Equatable {
        /// The PDF couldn't be written, so there's nothing to share.
        case notWritten
    }

    private let fileManager: FileManager
    private let directory: URL

    /// - Parameter directory: Where the files go. The app keeps them in its temporary directory, where earlier
    ///   versions of the app also left them.
    public init(fileManager: FileManager, directory: URL) {
        self.fileManager = fileManager
        self.directory = directory
    }

    /// Writes the PDF for the share sheet, named for when it was made, and returns the file's URL.
    public func write(_ pdf: BackupCreatePDFViewModel.GeneratedPDF) throws -> URL {
        let timestamp = VaultDateFormatter(timezone: .current).formatForFileName(date: pdf.createdDate)
        let url = directory.appending(path: "\(Self.namePrefix)\(timestamp).pdf")
        guard pdf.document.write(to: url) else { throw Error.notWritten }
        return url
    }

    /// Deletes a file that `write(_:)` made, if it's still there.
    public func delete(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    /// Deletes every backup PDF in the directory, and nothing else.
    public func deleteAll() {
        let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where Self.isBackupPDF(url) {
            delete(url)
        }
    }

    private static let namePrefix = "vault-export-"

    private static func isBackupPDF(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(namePrefix) && url.pathExtension == "pdf"
    }
}
