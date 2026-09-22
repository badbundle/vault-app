import Foundation
import SwiftUI

/// Full-width call to action for a `Form`: the one thing to do on this screen.
///
/// Sits in its own `Section` so the pill replaces the grouped row rather than
/// sitting inside one. A `.destructive` role tints it red.
struct ProminentActionButton: View {
    var title: String
    var systemImage: String
    var role: ButtonRole?
    var actionOptions: Set<AsyncButtonActionOption>
    var action: () async throws -> Void

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        actionOptions: Set<AsyncButtonActionOption> = Set(AsyncButtonActionOption.allCases),
        action: @escaping () async throws -> Void,
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.actionOptions = actionOptions
        self.action = action
    }

    var body: some View {
        AsyncButton(
            role: role,
            action: action,
            actionOptions: actionOptions,
            label: {
                ProminentActionLabel(title, systemImage: systemImage)
            },
            loading: {
                ProminentActionLabel(title, systemImage: systemImage, isLoading: true)
            },
        )
        .prominentActionButton()
    }
}

/// Label for a `Link` or `ShareLink` styled with `prominentActionButton()`.
struct ProminentActionLabel: View {
    var title: String
    var systemImage: String
    var isLoading: Bool

    init(_ title: String, systemImage: String, isLoading: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
    }

    var body: some View {
        HStack {
            Text(title)
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity)
        // Keep the pill the same size while loading: hide the label under the spinner.
        .opacity(isLoading ? 0 : 1)
        .overlay {
            if isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

extension View {
    /// Styles a `Button`, `Link` or `ShareLink` as the page's full-width call to action.
    func prominentActionButton() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.large)
            .noListBackground()
    }
}

#Preview {
    Form {
        Section {
            ProminentActionButton("Export & Save", systemImage: "square.and.arrow.up") {}
        }
        Section {
            ProminentActionButton("Delete All Data", systemImage: "trash.fill", role: .destructive) {}
        }
        Section {
            ProminentActionButton("Decrypt", systemImage: "lock.open.fill") {}
                .disabled(true)
        }
        Section {
            ProminentActionButton("Slow", systemImage: "clock") {
                try await Task.sleep(for: .seconds(3))
            }
        }
    }
}
