import SwiftUI
import TestHelpers
import UIKit

/// Snapshots `view` as an image, rendered in `colorScheme`.
///
/// Use this rather than `preferredColorScheme` in snapshot tests: that sets the style of the test
/// host's window rather than the snapshotted view's, so "dark" references come out light, and in
/// record runs it can outlast the test that set it. This sets the scheme on the view's environment
/// for SwiftUI, and on the host's traits for anything that resolves its colors from UIKit
/// (Liquid Glass, forms, text fields).
///
/// One thing still renders light: a button in the snapshotted view's own navigation bar keeps its
/// light-mode label offscreen, whatever the environment, traits or window style, so it vanishes
/// against a dark bar. Cover those buttons in the light references.
@MainActor
func assertSnapshot(
    of view: some View,
    colorScheme: ColorScheme,
    named name: String? = nil,
    file: StaticString = #file,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) {
    let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    assertSnapshot(
        of: view.environment(\.colorScheme, colorScheme),
        as: .image(traits: UITraitCollection(userInterfaceStyle: style)),
        named: name,
        file: file,
        fileID: fileID,
        filePath: filePath,
        testName: testName,
        line: line,
        column: column,
    )
}
