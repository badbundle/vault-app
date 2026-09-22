import Foundation
import SwiftUI

/// A button that supports binding to a Task action.
///
/// Attribution: https://www.swiftbysundell.com/articles/building-an-async-swiftui-button/
struct AsyncButton<Label: View, Loading: View>: View {
    var progressAlignment: Alignment = .center
    var role: ButtonRole?
    var action: () async throws -> Void
    var actionOptions = Set(ActionOption.allCases)
    @ViewBuilder var label: () -> Label
    var loading: () -> Loading

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDisabled = false
    @State private var showProgressView = false

    var body: some View {
        Button(
            role: role,
            action: {
                if actionOptions.contains(.disableButton) {
                    isDisabled = true
                }

                Task {
                    var progressViewTask: Task<Void, any Error>?

                    if actionOptions.contains(.showProgressView) {
                        progressViewTask = Task {
                            try await Task.sleep(for: .milliseconds(150))
                            try Task.checkCancellation()
                            showProgressView = true
                        }
                    }

                    defer {
                        progressViewTask?.cancel()
                        isDisabled = false
                        showProgressView = false
                    }

                    // Errors belong to the action: call sites either catch them inline or surface them
                    // through their own view model state. The button only drives loading and disabled state.
                    try? await action()
                }
            },
            label: {
                if showProgressView {
                    loading()
                } else {
                    label()
                }
            },
        )
        .disabled(isDisabled || !isEnabled)
    }
}

/// Top level rather than nested so the same option set fits every `AsyncButton` specialisation.
enum AsyncButtonActionOption: CaseIterable {
    case disableButton
    case showProgressView
}

extension AsyncButton {
    typealias ActionOption = AsyncButtonActionOption
}
