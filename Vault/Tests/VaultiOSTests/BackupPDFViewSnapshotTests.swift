import Foundation
import PDFKit
import SwiftUI
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed
@testable import VaultiOS

@MainActor
struct BackupPDFViewSnapshotTests {
    @Test
    func createPDF() {
        let sut = makeCreateSUT()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func savePDF_notSaved() {
        let sut = makeSaveSUT(viewModel: makeSaveViewModel())

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func savePDF_notSavedDark() {
        let sut = makeSaveSUT(viewModel: makeSaveViewModel())
            .environment(\.colorScheme, .dark)

        // The environment alone doesn't reach UIKit-backed rows; the host's traits do.
        assertSnapshot(of: sut, as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }

    @Test
    func savePDF_saved() {
        let viewModel = makeSaveViewModel()
        viewModel.shareSheetFinished(completed: true)
        let sut = makeSaveSUT(viewModel: viewModel)

        assertSnapshot(of: sut, as: .image)
    }
}

// MARK: - Helpers

extension BackupPDFViewSnapshotTests {
    private func makeCreateSUT() -> some View {
        let userDefaults = UserDefaults(suiteName: #function) ?? .standard
        userDefaults.removePersistentDomain(forName: #function)
        let viewModel = BackupCreatePDFViewModel(
            backupPassword: DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing),
            dataModel: anyVaultDataModel(),
            clock: EpochClockMock(currentTime: 100),
            defaults: Defaults(userDefaults: userDefaults),
            fileManager: .default,
        )
        return NavigationStack {
            BackupCreatePDFView(viewModel: viewModel, navigationPath: .constant(NavigationPath()))
        }
        .environment(anyVaultInjector())
        .framedForTest()
    }

    private func makeSaveSUT(viewModel: BackupGeneratedPDFViewModel) -> some View {
        NavigationStack {
            BackupSavePDFView(viewModel: viewModel, dismiss: {})
        }
        .environment(anyVaultInjector())
        .framedForTest()
    }

    private func makeSaveViewModel() -> BackupGeneratedPDFViewModel {
        BackupGeneratedPDFViewModel(pdf: blankPDF(), backupEventLogger: BackupEventLoggerMock())
    }

    /// Blank pages rather than a real backup: real backups encrypt with a random IV, so their QR codes
    /// would change every run.
    private func blankPDF() -> BackupCreatePDFViewModel.GeneratedPDF {
        let document = PDFDocument()
        for index in 0 ..< 2 {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 595, height: 842), for: .mediaBox)
            document.insert(page, at: index)
        }
        return BackupCreatePDFViewModel.GeneratedPDF(
            document: document,
            diskURL: URL(fileURLWithPath: "/tmp/backup.pdf"),
            size: .a4,
            dataHash: .init(value: Data(repeating: 0xAB, count: 32)),
            createdDate: Date(timeIntervalSince1970: 100),
        )
    }
}
