import Foundation
import VaultExport

struct VaultExportDataBlockHeaderGenerator: DataBlockHeaderGenerator {
    let dateCreated: Date
    let totalNumberOfPages: Int
    /// The backup's seal code, on every page so a page that comes loose can be matched to its backup.
    var sealCode: String?

    func makeHeader(pageNumber: Int) -> DataBlockHeader? {
        let date = dateFormatter.string(from: dateCreated)
        let dateText = if let sealCode {
            localized(key: "Created \(date) · Seal \(sealCode)")
        } else {
            localized(key: "Created \(date)")
        }
        let pageNumber = localized(key: "Page \(pageNumber) of \(totalNumberOfPages)")
        return DataBlockHeader(left: dateText, right: pageNumber)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}
