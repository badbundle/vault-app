import Foundation
import SwiftUI

extension View {
    /// Sizes the sheet this view is the content of to fit the view, with a drag indicator.
    ///
    /// The sheet hugs the content rather than snapping to `.medium`, which would leave half the sheet empty below a
    /// short list of cards. It's measured rather than fixed so Dynamic Type sizes still fit, and it follows the content
    /// as it grows or shrinks. Leave room above the content for the drag indicator.
    func fittedSheet() -> some View {
        modifier(FittedSheetModifier())
    }
}

private struct FittedSheetModifier: ViewModifier {
    @State private var contentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                contentHeight = newValue
            }
            // Until the first measurement lands a zero-height detent is invalid
            // (UIKit logs and ignores it), so fall back to `.medium` for that pass.
            .presentationDetents([contentHeight > 0 ? .height(contentHeight) : .medium])
            // Detents only apply to phone-style sheets; this keeps the iPad
            // form sheet from opening as a tall, mostly empty panel.
            .presentationSizing(.fitted)
            .presentationDragIndicator(.visible)
    }
}
