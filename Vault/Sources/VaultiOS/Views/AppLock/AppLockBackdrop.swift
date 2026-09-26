import Foundation
import SwiftUI
import VaultAppIcon

/// The vault door from the app icon, alone on a calm background: the privacy cover, and the backdrop of the lock
/// screen.
///
/// The door sits at the same height whatever is shown beneath it, so the cover and the lock screen swap without it
/// moving.
struct AppLockBackdrop<Details: View, Action: View>: View {
    /// What the door is doing: `nil` leaves it shut.
    var doorTransition: VaultLockTransition?
    /// Called when the door's mechanism seats, when it's opening.
    var onDoorClick: () -> Void
    @ViewBuilder var details: () -> Details
    @ViewBuilder var action: () -> Action

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(
        doorTransition: VaultLockTransition? = nil,
        onDoorClick: @escaping () -> Void = {},
        @ViewBuilder details: @escaping () -> Details,
        @ViewBuilder action: @escaping () -> Action,
    ) {
        self.doorTransition = doorTransition
        self.onDoorClick = onDoorClick
        self.details = details
        self.action = action
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 28) {
                door
                    .frame(width: doorSize, height: doorSize)
                details()
            }
            .frame(maxWidth: .infinity)
            // The door's centre a third of the way down.
            .padding(.top, max(0, proxy.size.height / 3 - doorSize / 2))
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottom) {
            action()
        }
        .background {
            background
                .ignoresSafeArea()
        }
    }

    private var doorSize: Double {
        verticalSizeClass == .compact ? 72 : 112
    }

    private var appearance: VaultAppIconAppearance {
        colorScheme == .dark ? .dark : .light
    }

    private var door: some View {
        Group {
            if let doorTransition {
                VaultLockAnimationView(
                    transition: doorTransition,
                    appearance: appearance,
                    metrics: .compact,
                    onClick: onDoorClick,
                )
            } else {
                VaultLockGlyphView(appearance: appearance, metrics: .compact)
            }
        }
        .accessibilityHidden(true)
    }

    /// A glow of the app icon's blue behind the door, fading into the system background.
    private var background: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(
                colors: [Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14), .clear],
                center: UnitPoint(x: 0.5, y: 1 / 3),
                startRadius: 0,
                endRadius: 360,
            )
        }
    }
}

extension AppLockBackdrop where Details == EmptyView, Action == EmptyView {
    /// The door alone.
    init() {
        self.init(details: { EmptyView() }, action: { EmptyView() })
    }
}
