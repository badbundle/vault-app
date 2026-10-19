import Foundation
import SwiftUI
import VaultAppIcon

/// The vault door from the app icon, alone on a calm background: the privacy cover, and the backdrop of the lock
/// screen.
///
/// The door sits at the same height whatever is shown beneath it, so the cover and the lock screen swap without it
/// moving. It's centred across the whole screen, not its safe area, which is wider on one side than the other on some
/// screens, such as the iPhone Duo's, folded and unfolded. What's beneath it is laid out in the widest band centred on
/// the screen that stays inside the safe area, so it's lined up under the door, unless that band is too narrow to read
/// comfortably. Then, and for words at the accessibility text sizes, which need all the width they can get, it moves
/// across to be under the door as far as it can while staying inside the safe area.
struct AppLockBackdrop<Details: View, Action: View>: View {
    /// What the door is doing: `nil` leaves it shut.
    var doorTransition: VaultLockTransition?
    /// Called when the door's mechanism seats, when it's opening.
    var onDoorClick: () -> Void
    @ViewBuilder var details: () -> Details
    @ViewBuilder var action: () -> Action

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            // How far the screen's centre is from the safe area's, along the width.
            let offCentre = (proxy.safeAreaInsets.trailing - proxy.safeAreaInsets.leading) / 2
            let safeWidth = proxy.size.width
            VStack(spacing: 28) {
                door
                    .frame(width: doorSize, height: doorSize)
                    .offset(x: offCentre)
                details()
                    .modifier(CentredUnderTheDoor(
                        offCentre: offCentre,
                        safeWidth: safeWidth,
                        minimumWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : Self.minimumWidthUnderTheDoor,
                    ))
            }
            .frame(maxWidth: .infinity)
            // The door's centre a third of the way down.
            .padding(.top, max(0, proxy.size.height / 3 - doorSize / 2))
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) {
                action()
                    .modifier(CentredUnderTheDoor(
                        offCentre: offCentre,
                        safeWidth: safeWidth,
                        minimumWidth: Self.minimumWidthUnderTheDoor,
                    ))
            }
        }
        .background {
            background
                .ignoresSafeArea()
        }
    }

    /// The narrowest band what's under the door is laid out in, to line up under it. Where the band is narrower, it
    /// keeps the safe area's width and moves across only as far as it can.
    private static var minimumWidthUnderTheDoor: Double {
        280
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

/// Lines up what's under the door under it. Where the band centred on the screen that stays inside the safe area is at
/// least `minimumWidth` wide, it's laid out in that band, centred under the door. Otherwise it's laid out across the
/// safe area, and moves across under the door as far as it can while staying inside it: all the way where it fits, and
/// less, or not at all, where it's too wide to.
private struct CentredUnderTheDoor: ViewModifier {
    /// How far the door is from the safe area's centre.
    var offCentre: Double
    var safeWidth: Double
    /// The narrowest band to lay it out in.
    var minimumWidth: Double

    @State private var width = 0.0

    func body(content: Content) -> some View {
        if band >= minimumWidth {
            content
                .frame(maxWidth: band)
                .offset(x: offCentre)
        } else {
            content
                .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
                .offset(x: shift)
        }
    }

    /// The safe area's width, less the difference between its two sides' insets.
    private var band: Double {
        max(0, safeWidth - 2 * abs(offCentre))
    }

    private var shift: Double {
        let room = max(0, (safeWidth - width) / 2)
        return min(max(offCentre, -room), room)
    }
}

extension AppLockBackdrop where Details == EmptyView, Action == EmptyView {
    /// The door alone.
    init() {
        self.init(details: { EmptyView() }, action: { EmptyView() })
    }
}
