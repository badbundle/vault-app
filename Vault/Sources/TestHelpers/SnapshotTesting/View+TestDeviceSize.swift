import Foundation

#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Fixed width at the test device size, height whatever the content wants.
    ///
    /// Pins the regular vertical size class: UIKit reports compact for
    /// short frames, which would otherwise flip size-class-aware layouts
    /// into their landscape form for any test using a small height.
    ///
    /// - parameter height: the height to make the view (defaults to 1000pts)
    public func framedForTest(height: CGFloat = 1000) -> some View {
        // iPhone 14 width
        frame(width: 390, height: height)
            .environment(\.verticalSizeClass, .regular)
    }

    /// Landscape phone frame with the compact vertical size class the
    /// system would report for it.
    public func framedForLandscapeTest() -> some View {
        // iPhone 14 landscape
        frame(width: 844, height: 390)
            .environment(\.verticalSizeClass, .compact)
    }
}

#endif
