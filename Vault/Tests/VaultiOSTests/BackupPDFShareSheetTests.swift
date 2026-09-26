import Foundation
import Testing
import UIKit
@testable import VaultiOS

@MainActor
struct BackupPDFShareSheetTests {
    /// Copy counts as saved without saving anything, and puts the backup on the pasteboard. Markup can save a
    /// copy but doesn't count as saved. So the backup's share sheet offers neither.
    @Test
    func backupShareSheet_excludesCopyAndMarkup() {
        let controller = ShareSheetPresenter.makeActivityController(
            item: URL(fileURLWithPath: "/tmp/vault-export.pdf"),
            excludedActivityTypes: BackupSavePDFView.excludedShareActivities,
            onFinish: { _ in },
        )

        let excluded = Set(controller.excludedActivityTypes ?? [])
        #expect(excluded.isSuperset(of: [.copyToPasteboard, .markupAsPDF]))
    }

    @Test(arguments: [true, false])
    func shareSheet_reportsWhetherItCompleted(completed: Bool) throws {
        var finished = [Bool]()
        let controller = ShareSheetPresenter.makeActivityController(
            item: URL(fileURLWithPath: "/tmp/vault-export.pdf"),
            excludedActivityTypes: [],
            onFinish: { finished.append($0) },
        )

        let handler = try #require(controller.completionWithItemsHandler)
        handler(.print, completed, nil, nil)

        #expect(finished == [completed])
    }
}
