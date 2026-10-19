import SwiftUI
import UIKit

/// The crease of a screen that folds, such as the iPhone Duo's inner screen, while it's partly folded.
///
/// From iOS 27.1, UIKit tells an app how far open its screen's hinge is (`UIHingeInteraction`), but nothing tells it
/// where the crease is: there's no safe area, layout guide or trait for it. Vault assumes it runs through the middle of
/// the screen, parallel to its shorter sides. That's down the middle when the screen is wider than it's tall, held
/// open like a book, and across the middle when it's taller than it's wide, stood on a table like a laptop. It only
/// counts while the screen is partly folded: open flat, the screen keeps its usual layout.
///
/// What matters stays out of a band `bandWidth` wide, centred on the crease.
struct Crease: Equatable, Sendable {
    enum Axis: Equatable, Sendable {
        /// Down the screen, between a leading page and a trailing one.
        case vertical
        /// Across the screen, between a top half and a bottom half.
        case horizontal
    }

    var axis: Axis
    /// Where the crease is in the window's coordinate space, which is SwiftUI's global one: how far across it is when
    /// it's vertical, or how far down when it's horizontal.
    var position: Double

    /// The width of the band around the crease that content stays out of.
    static let bandWidth = 24.0

    init(axis: Axis, position: Double) {
        self.axis = axis
        self.position = position
    }

    /// The crease of a partly folded screen filled by a window with `bounds`: through its middle, parallel to its
    /// shorter sides.
    init(partlyFoldedWindowOf bounds: CGRect) {
        if bounds.width > bounds.height {
            self.init(axis: .vertical, position: bounds.midX)
        } else {
            self.init(axis: .horizontal, position: bounds.midY)
        }
    }

    /// How the band around the crease divides a view whose frame in the window's coordinate space is `frame`, or
    /// `nil` if the band doesn't cross it, with room on both sides.
    func split(_ frame: CGRect) -> CreaseSplit? {
        let (start, length) = switch axis {
        case .vertical: (frame.minX, frame.width)
        case .horizontal: (frame.minY, frame.height)
        }
        let before = position - start - Self.bandWidth / 2
        let after = start + length - position - Self.bandWidth / 2
        guard before > 0, after > 0 else { return nil }
        return CreaseSplit(axis: axis, before: before, after: after)
    }
}

/// How the band around a crease divides a view: the room on each side of it, across the crease.
struct CreaseSplit: Equatable, Sendable {
    var axis: Crease.Axis
    /// The room before the band: the leading page's width, or the top half's height.
    var before: Double
    /// The room after the band: the trailing page's width, or the bottom half's height.
    var after: Double

    /// Where the room after the band starts.
    var afterStart: Double {
        before + Crease.bandWidth
    }
}

extension EnvironmentValues {
    /// The crease of the screen while it's partly folded, if it has one: `nil` on a screen that doesn't fold, or isn't
    /// partly folded. Set by `observesCrease()`.
    @Entry var crease: Crease?
}

extension View {
    /// Sets `\.crease` for this view and everything in it, from the hinge of the screen it's on. For the root of a
    /// window: what's in a window of its own, such as the lock screen's, needs its own.
    ///
    /// A crease already set in the environment, such as by a test or a preview, wins.
    func observesCrease() -> some View {
        modifier(CreaseObserver())
    }
}

private struct CreaseObserver: ViewModifier {
    @Environment(\.crease) private var injected
    @State private var observed: Crease?

    func body(content: Content) -> some View {
        content
            .environment(\.crease, injected ?? observed)
            .background {
                if #available(iOS 27.1, *) {
                    HingeObserver { observed = $0 }
                        .accessibilityHidden(true)
                }
            }
    }
}

/// Watches the hinge of the screen it's on, and reports where the crease is while it's partly folded.
@available(iOS 27.1, *)
private struct HingeObserver: UIViewRepresentable {
    var onChange: (Crease?) -> Void

    func makeUIView(context _: Context) -> HingeView {
        let view = HingeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HingeView, context _: Context) {
        view.onChange = onChange
    }

    final class HingeView: UIView {
        var onChange: ((Crease?) -> Void)?
        private var isPartlyFolded = false
        private var reported: Crease?
        private var windowSize: CGSize?

        override init(frame: CGRect) {
            super.init(frame: frame)
            // Called with the hinge as it is, once the view is in a window, and again whenever it moves. `hinge` is
            // nil on a screen without one.
            addInteraction(UIHingeInteraction { [weak self] _, update in
                self?.isPartlyFolded = update.hinge?.status == .partiallyOpen
                self?.report()
            })
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // The window turned, so the crease did too. Reported after this layout pass, which SwiftUI may be in.
            guard window?.bounds.size != windowSize else { return }
            windowSize = window?.bounds.size
            DispatchQueue.main.async { [weak self] in
                self?.report()
            }
        }

        private func report() {
            let crease = isPartlyFolded ? window.map { Crease(partlyFoldedWindowOf: $0.bounds) } : nil
            guard crease != reported else { return }
            reported = crease
            onChange?(crease)
        }
    }
}

extension View {
    /// Lays this view out on one side of a vertical crease that runs through it, so nothing in it sits across the
    /// crease: on the side with more room, the trailing one if they're even. For a view that fills the window held
    /// open like a book, that's one of its pages. It's left as it is where the crease is horizontal, and where neither
    /// side is at least `minimumWidth` wide, as in a narrow sheet in the middle of the screen.
    func keepsToOnePageOfTheCrease(minimumWidth: Double = 320) -> some View {
        modifier(OnePageOfTheCrease(minimumWidth: minimumWidth))
    }
}

private struct OnePageOfTheCrease: ViewModifier {
    var minimumWidth: Double

    @Environment(\.crease) private var crease
    @State private var extent: HorizontalExtent?

    func body(content: Content) -> some View {
        content
            .frame(width: page.map { CGFloat($0.width) })
            .frame(maxWidth: .infinity, alignment: page?.alignment ?? .center)
            .onGeometryChange(for: HorizontalExtent.self) { HorizontalExtent($0) } action: { extent = $0 }
    }

    private var page: (width: Double, alignment: Alignment)? {
        guard let crease, crease.axis == .vertical, let extent,
              let split = crease.split(extent.frame), max(split.before, split.after) >= minimumWidth
        else { return nil }
        return split.before > split.after ? (split.before, .leading) : (split.after, .trailing)
    }
}

/// Where a view is across the window, for a vertical crease. Only across, so it doesn't change as the view scrolls, or
/// as a sheet slides up.
struct HorizontalExtent: Equatable {
    var minX: Double
    var width: Double

    init(_ proxy: GeometryProxy) {
        let frame = proxy.frame(in: .global)
        minX = frame.minX
        width = frame.width
    }

    /// The view's frame across the window, with no height.
    var frame: CGRect {
        CGRect(x: minX, y: 0, width: width, height: 0)
    }
}
