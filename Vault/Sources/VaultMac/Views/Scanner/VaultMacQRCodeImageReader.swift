import AppKit
import Vision

/// Reads the QR codes in an image file the user picked.
enum VaultMacQRCodeImageReader {
    /// The text of every QR code in the image, or none if it isn't an image Vault can read. Read off the main actor,
    /// as finding the codes in a large image takes a while.
    nonisolated static func codes(in url: URL) async -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(url: url)
        guard (try? handler.perform([request])) != nil else { return [] }
        return request.results?.compactMap(\.payloadStringValue) ?? []
    }

    /// Asks the user for an image, and reads its QR codes.
    @MainActor
    static func chooseImage() async -> [String]? {
        let panel = NSOpenPanel()
        VaultMacPanels.prepare(panel)
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image of a QR code."
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        return await codes(in: url)
    }
}
