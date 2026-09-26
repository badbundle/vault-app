import Foundation
import SwiftUI

/// The buttons along the bottom of a walkthrough step: back to the step before, and on to the next.
struct DetailEditorActionBar: View {
    var showsBackButton: Bool
    var primaryTitle: String
    var isPrimaryEnabled: Bool
    var goBack: () -> Void
    var primaryAction: () async -> Void

    @ScaledMetric(relativeTo: .body) private var backButtonSize: Double = 50

    var body: some View {
        HStack(spacing: 12) {
            if showsBackButton {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: backButtonSize - 16, height: backButtonSize - 16)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Back")
                .transition(.scale.combined(with: .opacity))
            }

            AsyncButton {
                await primaryAction()
            } label: {
                Text(primaryTitle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: backButtonSize - 16)
            } loading: {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: backButtonSize - 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .disabled(!isPrimaryEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.snappy, value: showsBackButton)
    }
}

#Preview {
    VStack {
        Spacer()
        DetailEditorActionBar(
            showsBackButton: true,
            primaryTitle: "Continue",
            isPrimaryEnabled: true,
            goBack: {},
            primaryAction: {},
        )
    }
}
