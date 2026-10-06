import AppKit
import AVFoundation
import SwiftUI
import Vision

/// Reads QR codes from the Mac's camera, or Continuity Camera: the text of each code it sees, as it sees it.
///
/// Nothing it sees is kept: each frame is only looked at for codes, and the session stops when the view goes.
struct VaultMacQRCodeScanner: NSViewRepresentable {
    /// Called on the main actor with each code's text, every time a code is seen.
    var didScan: @MainActor (String) -> Void
    /// Called if no camera can be used.
    var didFail: @MainActor (VaultMacQRCodeScannerFailure) -> Void

    func makeNSView(context: Context) -> ScannerView {
        let view = ScannerView()
        context.coordinator.start(in: view)
        return view
    }

    func updateNSView(_: ScannerView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_: ScannerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class ScannerView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
            setAccessibilityIdentifier("scanner.camera")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }

    /// The capture session, which is set up on the main actor, then started and stopped on the scanner's queue, as
    /// AVFoundation asks, since starting it blocks. `AVCaptureSession` is documented thread-safe, so it's marked
    /// `@unchecked Sendable` to cross to that queue.
    private final class CaptureSession: @unchecked Sendable { // swiftlint:disable:this no_unchecked_sendable
        let session = AVCaptureSession()
    }

    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: VaultMacQRCodeScanner
        private let capture = CaptureSession()
        private let queue = DispatchQueue(label: "com.badbundle.vault.qr-scanner")

        private var session: AVCaptureSession {
            capture.session
        }

        init(parent: VaultMacQRCodeScanner) {
            self.parent = parent
        }

        func start(in view: ScannerView) {
            Task {
                guard await AVCaptureDevice.requestAccess(for: .video) else {
                    parent.didFail(.notAllowed)
                    return
                }
                guard let device = Self.camera(), let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input)
                else {
                    parent.didFail(.noCamera)
                    return
                }
                session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    parent.didFail(.noCamera)
                    return
                }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: queue)
                output.metadataObjectTypes = [.qr]
                view.previewLayer.session = session
                let capture = capture
                queue.async { capture.session.startRunning() }
            }
        }

        func stop() {
            let capture = capture
            queue.async { capture.session.stopRunning() }
        }

        /// The Mac's own camera, or failing that, Continuity Camera or another one plugged in.
        private static func camera() -> AVCaptureDevice? {
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
                mediaType: .video,
                position: .unspecified,
            ).devices.first
        }

        nonisolated func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection,
        ) {
            let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            guard codes.isNotEmpty else { return }
            Task { @MainActor in
                for code in codes {
                    parent.didScan(code)
                }
            }
        }
    }
}

enum VaultMacQRCodeScannerFailure: Equatable {
    /// The user hasn't let Vault use the camera.
    case notAllowed
    /// There's no camera to use.
    case noCamera

    var message: String {
        switch self {
        case .notAllowed: "Vault can't use the camera. You can allow it in System Settings, under Privacy & Security."
        case .noCamera: "There's no camera to scan with. You can choose an image of the code instead."
        }
    }
}

/// Reads the QR codes in an image file the user picked.
enum VaultMacQRCodeImageReader {
    /// The text of every QR code in the image, or none if it isn't an image Vault can read.
    static func codes(in url: URL) -> [String] {
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
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image of a QR code."
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        return codes(in: url)
    }
}
