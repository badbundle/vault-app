import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct InterruptedEraseViewSnapshotTests {
    /// An erase the app was stopped in the middle of couldn't finish: the vault stays hidden, with a way to try again.
    @Test(arguments: [ColorScheme.light, .dark])
    func failed(colorScheme: ColorScheme) async {
        let viewModel = InterruptedEraseViewModel(erase: { throw TestError() })
        await viewModel.finish()

        let sut = InterruptedEraseView(viewModel: viewModel).framedForTest()

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }
}
