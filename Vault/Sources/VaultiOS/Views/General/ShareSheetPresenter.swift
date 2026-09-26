import Foundation
import SwiftUI
import UIKit

extension View {
    /// Presents the system share sheet for `items` while `isPresented` is true.
    ///
    /// Unlike `ShareLink`, this reports how the sheet closed: `onFinish` receives true when the user
    /// completed an action (saved to Files, printed, sent…) and false when they closed it without one.
    func shareSheet(
        isPresented: Binding<Bool>,
        items: [Any],
        onFinish: @escaping (_ completed: Bool) -> Void,
    ) -> some View {
        background(ShareSheetPresenter(isPresented: isPresented, items: items, onFinish: onFinish))
    }
}

/// An invisible view controller that presents `UIActivityViewController` from wherever it sits, so the
/// share sheet gets its normal system presentation rather than being wrapped in a SwiftUI sheet.
private struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var items: [Any]
    var onFinish: (Bool) -> Void

    func makeUIViewController(context _: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context _: Context) {
        guard isPresented, controller.presentedViewController == nil else { return }
        let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityController.completionWithItemsHandler = { _, completed, _, _ in
            isPresented = false
            onFinish(completed)
        }
        activityController.popoverPresentationController?.sourceView = controller.view
        controller.present(activityController, animated: true)
    }
}
