import SwiftUI
@testable import VaultiOS

/// The iPhone Duo's inner screen, partly folded: 951 by 669 points held open like a book, with the crease down the
/// middle, or 669 by 951 stood on a table, with the crease across it.
enum PartlyFoldedScreen {
    case book
    case tabletop

    var size: CGSize {
        switch self {
        case .book: CGSize(width: 951, height: 669)
        case .tabletop: CGSize(width: 669, height: 951)
        }
    }

    var crease: Crease {
        Crease(partlyFoldedWindowOf: CGRect(origin: .zero, size: size))
    }
}

extension View {
    /// Fills `screen`, partly folded: its crease is where `observesCrease()` would put it on the device, and the band
    /// around the crease that the view should stay out of is shaded, so the snapshot shows that it does.
    func partlyFolded(_ screen: PartlyFoldedScreen) -> some View {
        GeometryReader { proxy in
            // Snapshots are drawn away from the window's origin, so the crease is placed in the middle of where the
            // view is, as the observer places it in the middle of the window.
            self
                .environment(\.crease, Crease(partlyFoldedWindowOf: proxy.frame(in: .global)))
                .overlay(alignment: .topLeading) {
                    CreaseBand(crease: screen.crease)
                }
        }
        .frame(width: screen.size.width, height: screen.size.height)
    }
}

/// The band around `crease`, which is in the view's own coordinates.
private struct CreaseBand: View {
    var crease: Crease

    var body: some View {
        let band = Color.red.opacity(0.25)
        switch crease.axis {
        case .vertical:
            band
                .frame(width: Crease.bandWidth)
                .frame(maxHeight: .infinity)
                .offset(x: crease.position - Crease.bandWidth / 2)
        case .horizontal:
            band
                .frame(height: Crease.bandWidth)
                .frame(maxWidth: .infinity)
                .offset(y: crease.position - Crease.bandWidth / 2)
        }
    }
}
