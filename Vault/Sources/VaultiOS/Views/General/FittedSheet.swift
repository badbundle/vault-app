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

    /// Sizes the sheet this view is the content of to `height`, or `.large` while it's `nil`, and resizes it smoothly
    /// when the height changes.
    ///
    /// The first height is used straight away, as the sheet opens. `height` doesn't include the bottom safe area, which
    /// the sheet adds below it. A height taller than the sheet can be makes it full height.
    func animatedSheetHeight(_ height: CGFloat?) -> some View {
        modifier(AnimatedSheetHeightModifier(height: height))
    }

    /// Calls `action` with the height a sheet needs to show all of this scrolling view's content (such as a `Form`),
    /// whenever it changes.
    ///
    /// Pass the height of any bar along the bottom of the view, such as a `safeAreaBar`. It's measured separately
    /// because the sheet's bottom safe area comes and goes as the sheet resizes, and it's part of the view's bottom
    /// inset, which would otherwise make the height chase the sheet's size.
    func onFittedSheetHeightChange(
        bottomBarHeight: CGFloat = 0,
        perform action: @escaping (CGFloat) -> Void,
    ) -> some View {
        modifier(FittedSheetHeightMeasuringModifier(bottomBarHeight: bottomBarHeight, action: action))
    }

    /// Reports the height a sheet needs to show all of this scrolling view's content (such as a `Form`) to the
    /// sheet's `fittedSheetHeightReporter`. Does nothing in a sheet without one.
    func reportsFittedSheetHeight() -> some View {
        modifier(FittedSheetHeightReportingModifier())
    }
}

extension EnvironmentValues {
    /// Where a screen of a sheet reports the height it needs, rather than sizing the sheet itself.
    ///
    /// Set by a sheet whose screens replace one another, like the new-item sheet, which sizes itself to the screen
    /// it's showing and resizes smoothly as it moves from one to the next.
    @Entry var fittedSheetHeightReporter: FittedSheetHeightReporter?
}

/// Takes the height a screen of a sheet needs. See `fittedSheetHeightReporter`.
struct FittedSheetHeightReporter: Equatable, Sendable {
    /// Identifies where the heights go, so the environment only changes when that does, not every time the closure
    /// is made again.
    var id: UUID
    var report: @MainActor (CGFloat) -> Void

    @MainActor
    func callAsFunction(_ height: CGFloat) {
        report(height)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

private struct FittedSheetHeightMeasuringModifier: ViewModifier {
    var bottomBarHeight: CGFloat
    var action: (CGFloat) -> Void

    @State private var measurementPass = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Measurement?.self) { geometry in
                // Nothing's laid out yet.
                guard geometry.contentSize.height > 0 else { return nil }
                // Only the top inset: the bottom one is the bar and the safe area, and the sheet adds the safe area.
                let height = geometry.contentSize.height + geometry.contentInsets.top + bottomBarHeight
                // Whole points, so the layout settling by a fraction of a point doesn't resize the sheet.
                return Measurement(pass: measurementPass, height: height.rounded(.up))
            } action: { _, measurement in
                guard let measurement else { return }
                action(measurement.height)
            }
            // The first measurement isn't reported as a change, so it's asked for again once the view is on screen.
            .onAppear {
                measurementPass += 1
            }
    }

    private struct Measurement: Equatable {
        var pass: Int
        var height: CGFloat
    }
}

private struct FittedSheetHeightReportingModifier: ViewModifier {
    @Environment(\.fittedSheetHeightReporter) private var reporter

    func body(content: Content) -> some View {
        content.onFittedSheetHeightChange { height in
            reporter?(height)
        }
    }
}

private struct AnimatedSheetHeightModifier: ViewModifier {
    var height: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The detent the sheet is at.
    @State private var shownDetent: PresentationDetent = .large
    /// The detents offered: just the shown one, and while moving, the one it's moving to as well.
    @State private var offeredDetents: Set<PresentationDetent> = [.large]
    /// The tallest the sheet can be, measured while it's at `.large`, as it is until the first height lands.
    @State private var fullHeight: CGFloat?
    @State private var hasShownHeight = false
    /// Moves the sheet to the latest detent, then stops offering the one it came from.
    @State private var resizing: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                // A detent's height includes the navigation bar above the content, but not the safe area below it.
                proxy.size.height + proxy.safeAreaInsets.top
            } action: { sheetHeight in
                if offeredDetents == [.large], sheetHeight > 0 {
                    fullHeight = sheetHeight
                }
            }
            .presentationDetents(offeredDetents, selection: $shownDetent)
            // Offering two detents while moving between them would show the grabber for a moment, but the sheet only
            // ever fits its content, so there's nothing to drag it to.
            .presentationDragIndicator(.hidden)
            .onChange(of: height, initial: true) { _, newHeight in
                resize(to: newHeight)
            }
    }

    private func resize(to newHeight: CGFloat?) {
        let newDetent = detent(for: newHeight)
        let isFirstHeight = !hasShownHeight
        hasShownHeight = hasShownHeight || newHeight != nil
        guard newDetent != shownDetent else { return }
        // The first height lands as the sheet opens, so there's nothing on screen yet to resize.
        guard !isFirstHeight else {
            shownDetent = newDetent
            offeredDetents = [newDetent]
            return
        }
        // Swapping one detent for another makes the sheet jump to the new size, so both are offered for a moment and
        // the sheet moves from one to the other, which animates.
        offeredDetents.insert(newDetent)
        resizing?.cancel()
        resizing = Task { @MainActor in
            // After the new detent is offered, so the sheet can move to it.
            withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .snappy(duration: 0.4)) {
                shownDetent = newDetent
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            offeredDetents = [newDetent]
        }
    }

    /// The detent for `height`, or `.large` if the sheet can't be that tall.
    ///
    /// A height the sheet is only clamped from would still be a different detent to `.large`: offering it gives the
    /// sheet the look of a full-height one straight away, before it's grown, and a step whose height changes a little
    /// would resize a sheet that can't grow any further.
    private func detent(for height: CGFloat?) -> PresentationDetent {
        guard let height else { return .large }
        if let fullHeight, height >= fullHeight {
            return .large
        }
        return .height(height)
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
