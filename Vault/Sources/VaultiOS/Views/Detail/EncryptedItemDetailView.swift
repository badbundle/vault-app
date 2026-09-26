import Combine
import Foundation
import SwiftUI
import VaultAppIcon
import VaultFeed

struct EncryptedItemDetailView: View {
    @State private var viewModel: EncryptedItemDetailViewModel
    /// Signaled when the given `VaultItem` should be opened in place of this detail view.
    var openDetailSubject: PassthroughSubject<VaultItemEncryptionPayload, Never>
    /// Required to know the presentation context, so we know how this view should be dismissed.
    var presentationMode: Binding<PresentationMode>?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the vault door in the header is doing. `.decrypt` once the password has
    /// decrypted the item, which opens when the door has swung wide;
    /// `.decryptionFailed` when the password was wrong.
    @State private var lockTransition: VaultLockTransition?
    /// The decrypted item, held while the door opens.
    @State private var decryptedPayload: VaultItemEncryptionPayload?
    /// Counts wrong passwords: each one buzzes and replays the door's rattle.
    @State private var failedAttempts = 0
    @State private var lockClickCount = 0
    /// Matches `PlaceholderView`'s icon, to find the door in the header.
    @ScaledMetric(relativeTo: .largeTitle) private var doorSize: Double = 40

    init(
        viewModel: EncryptedItemDetailViewModel,
        openDetailSubject: PassthroughSubject<VaultItemEncryptionPayload, Never>,
        presentationMode: Binding<PresentationMode>? = nil,
    ) {
        self.viewModel = viewModel
        self.openDetailSubject = openDetailSubject
        self.presentationMode = presentationMode
    }

    private func dismiss() {
        presentationMode?.wrappedValue.dismiss()
    }

    var body: some View {
        Form {
            titleSection
            passwordEntrySection
        }
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.isLoading)
        .sensoryFeedback(.impact(weight: .heavy), trigger: lockClickCount)
        .sensoryFeedback(.error, trigger: failedAttempts)
        .onChange(of: viewModel.state) { _, newValue in
            switch newValue {
            case let .decrypted(item, encryptionKey):
                // Create a quasi-item that uses the metadata of the encrypted item, but with the contents
                // of the note.
                let quasiItem = VaultItem(metadata: viewModel.metadata, item: item)
                let payload = VaultItemEncryptionPayload(decryptedItem: quasiItem, encryptionKey: encryptionKey)
                if reduceMotion {
                    openDetailSubject.send(payload)
                } else {
                    decryptedPayload = payload
                    lockTransition = .decrypt
                }
            case let .decryptionError(error):
                failedAttempts += 1
                if !reduceMotion {
                    lockTransition = .decryptionFailed
                }
                AccessibilityNotification.Announcement(error.userTitle).post()
            case .base, .decrypting:
                // The error has gone, so the door has nothing more to rattle about.
                if lockTransition == .decryptionFailed {
                    lockTransition = nil
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                .tint(.red)
                .disabled(viewModel.isLoading)
            }
        }
    }

    /// The vault door and what it needs. A wrong password turns the whole cell into
    /// the error, white on red, flooding out from the door as it rattles.
    private var titleSection: some View {
        let error = viewModel.state.presentationError
        return Section {
            PlaceholderView(
                title: error?.userTitle ?? "Encrypted",
                subtitle: error == nil ? "A password is required to decrypt this item." : error?.userDescription,
                subtitleStyle: error == nil ? .secondary : .primary,
            ) {
                // All white on the red, like the text.
                vaultDoor(palette: error == nil ? doorAppearance.palette : .monochrome(.white))
            }
            .foregroundStyle(error == nil ? Color.primary : Color.white)
            .padding()
            .containerRelativeFrame(.horizontal)
            .accessibilityElement(children: .combine)
            .listRowBackground(
                ErrorFloodBackground(isFlooded: error != nil, origin: doorCenter)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: error != nil),
            )
        }
    }

    /// Where the door sits in the header: inside the placeholder's padding, below
    /// the row's own inset.
    private var doorCenter: CGPoint {
        CGPoint(x: 16 + doorSize / 2, y: 11 + 16 + doorSize / 2)
    }

    private var doorAppearance: VaultAppIconAppearance {
        colorScheme == .dark ? .dark : .light
    }

    /// The vault door from the app icon, as on a locked item. When the password
    /// decrypts the item the wheel works its combination and the door swings wide,
    /// and the item opens once it has; a wrong password rattles the door instead.
    private func vaultDoor(palette: VaultAppIconPalette) -> some View {
        Group {
            switch lockTransition {
            case .decrypt:
                VaultLockAnimationView(
                    transition: .decrypt,
                    palette: palette,
                    metrics: .compact,
                    onClick: { lockClickCount += 1 },
                    onFinished: {
                        if let decryptedPayload {
                            openDetailSubject.send(decryptedPayload)
                        }
                    },
                )
            case .decryptionFailed:
                VaultLockAnimationView(
                    transition: .decryptionFailed,
                    palette: palette,
                    metrics: .compact,
                    onFinished: { lockTransition = nil },
                )
                // A fresh run for every failure, even one that lands mid-rattle.
                .id(failedAttempts)
            case .lock, .unlock, nil:
                // An encrypted item is never locked or unlocked here: at rest, the door is shut.
                VaultLockGlyphView(palette: palette, metrics: .compact)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var passwordEntrySection: some View {
        Section {
            LabeledTextField(
                "Password",
                text: $viewModel.enteredEncryptionPassword,
                kind: .secure(),
                status: viewModel.state.presentationError == nil ? .none : .error(),
            )
            .secretTextInput(.verbatim)
            .disabled(viewModel.isDecrypted)
        }
        .onChange(of: viewModel.enteredEncryptionPassword) { _, _ in
            // When the text changes, reset the state.
            viewModel.resetState()
        }

        Section {
            ProminentActionButton("Decrypt", systemImage: "lock.open.fill") {
                await viewModel.startDecryption()
            }
            .disabled(!viewModel.canStartDecryption)
        }
        .animation(.snappy, value: viewModel.state)
    }
}

/// A row background that floods red from `origin` when `isFlooded`, and drains
/// back to the usual grouped background when it isn't.
private struct ErrorFloodBackground: View {
    var isFlooded: Bool
    var origin: CGPoint

    var body: some View {
        GeometryReader { proxy in
            // Just big enough to reach the far corner.
            let radius = hypot(
                max(origin.x, proxy.size.width - origin.x),
                max(origin.y, proxy.size.height - origin.y),
            )
            ZStack {
                Color(UIColor.secondarySystemGroupedBackground)
                Circle()
                    .fill(.red)
                    .frame(width: radius * 2, height: radius * 2)
                    // Never quite zero: a singular scale can't be inverted.
                    .scaleEffect(isFlooded ? 1 : 0.001)
                    .position(origin)
            }
            .clipped()
        }
    }
}
