import Combine
import SwiftUI
import TestHelpers
import Testing
@testable import VaultiOS

@MainActor
final class HorizontalTimerProgressBarViewSnapshotTests {
    @Test
    func layout_empty() {
        let view = HorizontalTimerProgressBarView(
            fractionCompleted: 0,
            color: .blue,
        ).frame(width: 150, height: 20)

        assertSnapshot(of: view, as: .image)
    }

    @Test
    func layout_halfFull() {
        let view = HorizontalTimerProgressBarView(
            fractionCompleted: 0.5,
            color: .blue,
        ).frame(width: 150, height: 20)

        assertSnapshot(of: view, as: .image)
    }

    @Test
    func layout_full() {
        let view = HorizontalTimerProgressBarView(
            fractionCompleted: 1,
            color: .blue,
        ).frame(width: 150, height: 20)

        assertSnapshot(of: view, as: .image)
    }

    @Test
    func layout_setsBackgroundColor() {
        let view = HorizontalTimerProgressBarView(
            fractionCompleted: 0.5,
            color: .blue,
            backgroundColor: .red,
        ).frame(width: 150, height: 20)

        assertSnapshot(of: view, as: .image)
    }

    @Test
    func redactedPlaceholder_showsEmptyProgressBar() {
        let view = HorizontalTimerProgressBarView(
            fractionCompleted: 0.5,
            color: .blue,
            backgroundColor: .gray,
        )
        .redacted(reason: .placeholder)
        .frame(width: 150, height: 20)

        assertSnapshot(of: view, as: .image)
    }

    @Test
    func redactedPrivacy_showsProgressStill() {
        let view = HorizontalTimerProgressBarView(fractionCompleted: 0.5, color: .blue)
            .redacted(reason: .privacy)
            .frame(width: 150, height: 20)

        assertSnapshot(of: view, as: .image)
    }

    /// Muted text over the track and white over the fill, changing where the fill ends.
    @Test
    func label_changesColorWhereFillEnds() {
        for colorScheme in [ColorScheme.light, .dark] {
            let view = HorizontalTimerProgressBarView(fractionCompleted: 0.25, color: .blue)
                .environment(\.timerBarLabel, "Code locked")
                .frame(width: 150, height: 12)
                .background(Color(.secondarySystemBackground))

            assertSnapshot(of: view, colorScheme: colorScheme, named: "\(colorScheme)")
        }
    }

    /// The white editing bar, on the accent background of a card being edited.
    @Test
    func label_editing() {
        for colorScheme in [ColorScheme.light, .dark] {
            let view = HorizontalTimerProgressBarView.editing
                .environment(\.timerBarLabel, "Tap to View")
                .frame(width: 150, height: 12)
                .background(Color.accentColor)

            assertSnapshot(of: view, colorScheme: colorScheme, named: "\(colorScheme)")
        }
    }
}
