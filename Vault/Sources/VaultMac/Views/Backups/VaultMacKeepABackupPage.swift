import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import VaultFeed

/// Keep a Backup: the whole vault, encrypted with the backup password and padded, as a PDF (G54, G57), saved where
/// the user chooses through the save panel, or printed. There's no temporary file and no share sheet (G43, G53).
struct VaultMacKeepABackupPage: View {
    @State var viewModel: BackupCreatePDFViewModel
    var saver: VaultMacBackupPDFSaver

    @State private var pdf: BackupCreatePDFViewModel.GeneratedPDF?
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                Picker("Paper Size", selection: $viewModel.size) {
                    ForEach(BackupCreatePDFViewModel.Size.allCases) { size in
                        Text(size.localizedTitle).tag(size)
                    }
                }
                VaultMacTextField("Password Hint", text: $viewModel.userHint, identifier: "backups.pdf.hint")
            } header: {
                Text("Options")
            } footer: {
                Text(
                    "An optional hint to help you remember the password. It's printed on the document in plain text, so anyone who sees it can read it.",
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button(pdf == nil ? "Create PDF" : "Create Again") {
                        Task { await viewModel.createPDF() }
                    }
                    .disabled(viewModel.state == .loading)
                    .accessibilityIdentifier("backups.pdf.create")
                    if viewModel.state == .loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    if let pdf {
                        Button("Print…") { printOnPaper(pdf) }
                            .accessibilityIdentifier("backups.pdf.print")
                        Button("Save…") { save(pdf) }
                            .keyboardShortcut("s")
                            .accessibilityIdentifier("backups.pdf.save")
                    }
                }
            } footer: {
                if let message = problem ?? viewModel.state.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if pdf != nil {
                    Text("The PDF is ready. Save it somewhere safe, or print it, then keep it away from this Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(viewModel.generatedPDFPublisher()) { generated in
            pdf = generated
            problem = nil
        }
        // Only kept while the page is open.
        .onDisappear { pdf = nil }
    }

    private func save(_ pdf: BackupCreatePDFViewModel.GeneratedPDF) {
        let panel = NSSavePanel()
        VaultMacPanels.prepare(panel)
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = BackupPDFTemporaryFiles.fileName(for: pdf)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try saver.save(pdf, to: url)
            problem = nil
        } catch {
            problem = "Vault couldn't save the PDF there. Choose another place and try again."
        }
    }

    private func printOnPaper(_ pdf: BackupCreatePDFViewModel.GeneratedPDF) {
        if saver.printOnPaper(pdf) {
            problem = nil
        }
    }
}

/// Saves or prints a backup PDF, and logs it as a backup once it's saved or printed, as the iOS share sheet does.
@MainActor
struct VaultMacBackupPDFSaver {
    enum Failure: Error, Equatable {
        case notWritten
    }

    var backupEventLogger: any BackupEventLogger
    /// Runs the print panel, and says whether it printed. The system's, unless a test's.
    var runPrint: @MainActor (PDFDocument) -> Bool = Self.runPrintPanel

    /// Writes the PDF to `url`, which the save panel gave, replacing what's there if the user said to.
    func save(_ pdf: BackupCreatePDFViewModel.GeneratedPDF, to url: URL) throws {
        guard let data = pdf.document.dataRepresentation() else { throw Failure.notWritten }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw Failure.notWritten
        }
        log(pdf)
    }

    /// Prints the PDF, and says whether it was printed.
    @discardableResult
    func printOnPaper(_ pdf: BackupCreatePDFViewModel.GeneratedPDF) -> Bool {
        guard runPrint(pdf.document) else { return false }
        log(pdf)
        return true
    }

    private func log(_ pdf: BackupCreatePDFViewModel.GeneratedPDF) {
        backupEventLogger.exportedToPDF(backupDate: pdf.createdDate, hash: pdf.dataHash, vaultToken: pdf.vaultToken)
    }

    static func runPrintPanel(_ document: PDFDocument) -> Bool {
        guard let operation = document.printOperation(
            for: NSPrintInfo.shared,
            scalingMode: .pageScaleToFit,
            autoRotate: true,
        ) else { return false }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        guard operation.run() else { return false }
        // Printed, or saved as a PDF from the print panel: a backup kept. Opened in Preview, or sent somewhere from
        // the panel's PDF menu, isn't one Vault can count on.
        return [.spool, .save].contains(operation.printInfo.jobDisposition)
    }
}

extension BackupCreatePDFViewModel.State {
    fileprivate var errorMessage: String? {
        guard case let .error(error) = self else { return nil }
        return error.userDescription ?? error.userTitle
    }
}
