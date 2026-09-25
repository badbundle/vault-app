import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultiOS

@MainActor
struct LabeledTextFieldSnapshotTests {
    @Test
    func plain() {
        let sut = Form {
            Section {
                LabeledTextField("Empty", text: .constant(""), prompt: "Only shown while focused")
                LabeledTextField("Filled", text: .constant("Some text"))
                LabeledTextField(
                    "Long Value",
                    text: .constant("A value that's much too long to fit on a single line of the field"),
                )
            }
        }

        snapshotScenarios(view: sut, dynamicTypeSizes: [.xSmall, .medium, .xxLarge, .accessibility2])
    }

    @Test
    func secure() {
        let sut = Form {
            Section {
                LabeledTextField("Empty", text: .constant(""), kind: .secure())
                LabeledTextField("Masked", text: .constant("password"), kind: .secure())
                LabeledTextField(
                    "Masked, Can Reveal",
                    text: .constant("password"),
                    kind: .secure(isRevealed: .constant(false)),
                )
                LabeledTextField(
                    "Revealed",
                    text: .constant("password"),
                    kind: .secure(isRevealed: .constant(true)),
                )
            }
        }

        snapshotScenarios(view: sut)
    }

    @Test
    func multiline() {
        let sut = Form {
            Section {
                LabeledTextField("Empty", text: .constant(""), kind: .multiline(minLines: 3))
                LabeledTextField("Filled", text: .constant("First line\nSecond line"), kind: .multiline(minLines: 3))
                LabeledTextField(
                    "Grown",
                    text: .constant("One\nTwo\nThree\nFour\nFive"),
                    kind: .multiline(minLines: 3),
                )
                LabeledTextField("Single Line", text: .constant(""), kind: .multiline(minLines: 1))
            }
        }

        snapshotScenarios(view: sut)
    }

    @Test
    func status() {
        let sut = Form {
            Section {
                LabeledTextField("Valid", text: .constant("JBSWY3DPEHPK3PXP"), status: .valid)
                LabeledTextField("Error", text: .constant("ABC!"), status: .error())
                LabeledTextField(
                    "Error With Message",
                    text: .constant("   "),
                    status: .error(message: "Enter some text, not just spaces."),
                )
                LabeledTextField("Empty Error", text: .constant(""), kind: .secure(), status: .error())
            }
        }

        snapshotScenarios(view: sut)
    }

    @Test
    func monospacedValue() {
        let sut = Form {
            Section {
                LabeledTextField("Empty", text: .constant(""))
                LabeledTextField("Filled", text: .constant("JBSWY3DPEHPK3PXP"))
                LabeledTextField("Note", text: .constant("# Title\nContents"), kind: .multiline(minLines: 3))
                    .font(.subheadline)
            }
            .fontDesign(.monospaced)
        }

        snapshotScenarios(view: sut)
    }

    @Test
    func disabled() {
        let sut = Form {
            Section {
                LabeledTextField("Empty", text: .constant(""))
                LabeledTextField("Filled", text: .constant("Some text"))
            }
            .disabled(true)
        }

        snapshotScenarios(view: sut, dynamicTypeSizes: [.medium])
    }
}

// MARK: - Helpers

extension LabeledTextFieldSnapshotTests {
    private func snapshotScenarios(
        view: some View,
        dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge],
        testName: String = #function,
    ) {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = view
                    .dynamicTypeSize(dynamicTypeSize)
                    .preferredColorScheme(colorScheme)
                    .framedForTest(height: 700)

                assertSnapshot(
                    of: snapshottingView,
                    as: .image,
                    named: "\(colorScheme)_\(dynamicTypeSize)",
                    testName: testName,
                )
            }
        }
    }
}
