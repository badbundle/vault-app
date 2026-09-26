import Foundation
import SwiftUI
import UIKit

extension View {
    /// Presents the system share sheet for `item` whenever it's non-nil.
    ///
    /// Unlike `ShareLink`, this reports how the sheet closed: `onFinish` receives true when the user
    /// completed an action (saved to Files, printed, sent…) and false when they closed it without one.
    /// It's called once, when the sheet has closed, and should set `item` back to nil.
    func shareSheet(
        item: URL?,
        excludedActivityTypes: [UIActivity.ActivityType] = [],
        onFinish: @escaping (_ completed: Bool) -> Void,
    ) -> some View {
        background(ShareSheetPresenter(
            item: item,
            excludedActivityTypes: excludedActivityTypes,
            onFinish: onFinish,
        ))
    }
}

/// An invisible view controller that presents `UIActivityViewController` from wherever it sits, so the
/// share sheet gets its normal system presentation rather than being wrapped in a SwiftUI sheet.
struct ShareSheetPresenter: UIViewControllerRepresentable {
    var item: URL?
    var excludedActivityTypes: [UIActivity.ActivityType]
    var onFinish: (Bool) -> Void

    func makeUIViewController(context _: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context _: Context) {
        guard let item, controller.presentedViewController == nil else { return }
        let activityController = Self.makeActivityController(
            item: item,
            excludedActivityTypes: excludedActivityTypes,
            onFinish: onFinish,
        )
        activityController.popoverPresentationController?.sourceView = controller.view
        controller.present(activityController, animated: true)
    }

    /// The share sheet for `item`, without the excluded activities.
    static func makeActivityController(
        item: URL,
        excludedActivityTypes: [UIActivity.ActivityType],
        onFinish: @escaping (Bool) -> Void,
    ) -> UIActivityViewController {
        let activityController = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        activityController.excludedActivityTypes = excludedActivityTypes
        activityController.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return activityController
    }
}
