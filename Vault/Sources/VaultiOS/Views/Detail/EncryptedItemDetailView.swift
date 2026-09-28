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
    ///
    /// The text and door turn white only where the red has reached: the header is
    /// drawn as usual outside the flood, and in white inside it. The red is drawn in
    /// the row too, so they all move together. As the row's background, the red
    /// started a few frames after the text turned white, which left the cell blank
    /// in light mode.
    private var titleSection: some View {
        let error = viewModel.state.presentationError
        let flood = ErrorFloodShape(progress: error == nil ? 0 : 1, origin: doorCenter)
        let floodAnimation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.45)
        return Section {
            header(error: error, palette: doorAppearance.palette, isEcho: false)
                .foregroundStyle(Color.primary)
                .containerRelativeFrame(.horizontal)
                .mask {
                    flood.inverted()
                        .fill(style: FillStyle(eoFill: true))
                        .animation(floodAnimation, value: flood.progress)
                }
                .overlay {
                    header(error: error, palette: .monochrome(.white), isEcho: true)
                        .foregroundStyle(Color.white)
                        .mask { flood.animation(floodAnimation, value: flood.progress) }
                        .accessibilityHidden(true)
                }
                .background {
                    flood
                        .fill(.red)
                        .animation(floodAnimation, value: flood.progress)
                        .clipped()
                }
                .accessibilityElement(children: .combine)
                // Tells a wrong password apart from the prompt for one, for the UI tests.
                .accessibilityIdentifier(error == nil ? "encrypted-item.header" : "encrypted-item.error")
                // The flood covers the whole row, insets and all.
                .listRowInsets(EdgeInsets())
        }
    }

    /// The door, title and subtitle, inset from the row's edges. `isEcho` for the
    /// white copy over the flood, whose door doesn't click or finish anything.
    private func header(error: PresentationError?, palette: VaultAppIconPalette, isEcho: Bool) -> some View {
        PlaceholderView(
            title: error?.userTitle ?? "Encrypted",
            subtitle: error == nil ? "A password is required to decrypt this item." : error?.userDescription,
            subtitleStyle: error == nil ? .secondary : .primary,
        ) {
            vaultDoor(palette: palette, isEcho: isEcho)
        }
        .padding()
        .padding(.vertical, Self.rowVerticalInset)
    }

    /// The top and bottom inset a row has by default, which the header keeps as
    /// padding instead.
    private static let rowVerticalInset: Double = 15

    /// Where the door sits in the header: inside the placeholder's padding, below
    /// the row's own inset.
    private var doorCenter: CGPoint {
        CGPoint(x: 16 + doorSize / 2, y: Self.rowVerticalInset + 16 + doorSize / 2)
    }

    private var doorAppearance: VaultAppIconAppearance {
        colorScheme == .dark ? .dark : .light
    }

    /// The vault door from the app icon, as on a locked item. When the password
    /// decrypts the item the wheel works its combination and the door swings wide,
    /// and the item opens once it has; a wrong password rattles the door instead.
    private func vaultDoor(palette: VaultAppIconPalette, isEcho: Bool) -> some View {
        Group {
            switch lockTransition {
            case .decrypt:
                VaultLockAnimationView(
                    transition: .decrypt,
                    palette: palette,
                    metrics: .compact,
                    onClick: {
                        guard !isEcho else { return }
                        lockClickCount += 1
                    },
                    onFinished: {
                        guard !isEcho, let decryptedPayload else { return }
                        openDetailSubject.send(decryptedPayload)
                    },
                )
            case .decryptionFailed:
                VaultLockAnimationView(
                    transition: .decryptionFailed,
                    palette: palette,
                    metrics: .compact,
                    onFinished: {
                        guard !isEcho else { return }
                        lockTransition = nil
                    },
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
            .accessibilityIdentifier("encrypted-item.password")
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
            .accessibilityIdentifier("encrypted-item.decrypt")
        }
        .animation(.snappy, value: viewModel.state)
    }
}

/// A circle that floods out from `origin`, from nothing at a `progress` of 0 to
/// just big enough to reach the far corner at 1. Inverted, it's everything the
/// flood hasn't reached yet, to fill with the even-odd rule.
private struct ErrorFloodShape: Shape {
    var progress: Double
    var origin: CGPoint
    private var isInverted = false

    init(progress: Double, origin: CGPoint) {
        self.progress = progress
        self.origin = origin
    }

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func inverted() -> Self {
        var shape = self
        shape.isInverted = true
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let radius = hypot(
            max(origin.x - rect.minX, rect.maxX - origin.x),
            max(origin.y - rect.minY, rect.maxY - origin.y),
        ) * progress
        var path = Path()
        if isInverted {
            path.addRect(rect)
        }
        path.addEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
        return path
    }
}
