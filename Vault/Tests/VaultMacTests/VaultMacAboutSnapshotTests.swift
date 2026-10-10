import AppKit
import SwiftUI
import TestHelpers
import Testing
@testable import VaultMac

/// The About and Help windows show every link's title in full, with none cut off.
@MainActor
struct VaultMacAboutSnapshotTests {
    @Test(arguments: MacAppearance.allCases)
    func about(appearance: MacAppearance) {
        let view = VaultMacAboutView(version: "Version 2.0 (100016)", openHelp: { _ in })

        assertSnapshot(
            of: view,
            as: .macWindow(width: 400, height: 760, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    /// The Help window's sidebar, at its default width, with every page's title in full.
    ///
    /// In light only and with nothing selected: drawn off screen, the sidebar's dark appearance and its selection lose
    /// their colours.
    @Test
    func help() {
        let model = VaultMacHelpModel()
        model.selection = nil
        let view = VaultMacHelpView(model: model)

        assertSnapshot(of: view, as: .macWindow(width: 860, height: 600))
    }
}
