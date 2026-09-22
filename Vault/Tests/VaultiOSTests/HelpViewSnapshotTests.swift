import Foundation
import TestHelpers
import Testing
@testable import VaultiOS

@MainActor
final class HelpViewSnapshotTests {
    @Test
    func deviceSize() {
        let view = HelpView(viewModel: .init())
            .framedForTest()

        assertSnapshot(of: view, as: .image)
    }
}
