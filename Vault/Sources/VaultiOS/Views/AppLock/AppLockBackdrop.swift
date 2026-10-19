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
///
/// On a screen that's partly folded, nothing sits across the crease (see `Crease`). Held open like a book, the door and
/// what's beneath it are in the middle of the leading page, and the action is in the middle of the trailing one. Stood
/// on a table like a laptop, the door and what's beneath it are in the top half, with the door's centre a third of the
/// way down it, and the action is in the middle of the bottom half.
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
    @Environment(\.crease) private var crease

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
            switch Fold(crease?.split(proxy.frame(in: .global))) {
            case let .book(split):
                book(split, in: proxy)
            case let .tabletop(split):
                tabletop(split, in: proxy)
            case nil:
                unfolded(in: proxy)
            }
        }
        .background {
            GeometryReader { screen in
                background(glowCentre: glowCentre(on: screen.frame(in: .global)))
            }
            .ignoresSafeArea()
        }
    }

    private func unfolded(in proxy: GeometryProxy) -> some View {
        // How far the screen's centre is from the safe area's, along the width.
        let offCentre = (proxy.safeAreaInsets.trailing - proxy.safeAreaInsets.leading) / 2
        let safeWidth = proxy.size.width
        return VStack(spacing: 28) {
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

    /// Open like a book: the door and what's beneath it on the leading page, with the door's centre a third of the way
    /// down as when unfolded, and the action in the middle of the trailing page.
    private func book(_ split: CreaseSplit, in proxy: GeometryProxy) -> some View {
        HStack(spacing: Crease.bandWidth) {
            VStack(spacing: 28) {
                door
                    .frame(width: doorSize, height: doorSize)
                details()
            }
            .frame(width: split.before)
            .padding(.top, max(0, proxy.size.height / 3 - doorSize / 2))
            .frame(maxHeight: .infinity, alignment: .top)

            action()
                .frame(width: split.after)
                .frame(maxHeight: .infinity)
        }
    }

    /// Stood on a table: the door and what's beneath it in the top half, with the door's centre a third of the way down
    /// it, and the action in the middle of the bottom half. Across the screen, they're lined up as when unfolded.
    private func tabletop(_ split: CreaseSplit, in proxy: GeometryProxy) -> some View {
        let offCentre = (proxy.safeAreaInsets.trailing - proxy.safeAreaInsets.leading) / 2
        let safeWidth = proxy.size.width
        return VStack(spacing: Crease.bandWidth) {
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
            .padding(.top, max(0, split.before / 3 - doorSize / 2))
            .frame(height: split.before, alignment: .top)

            action()
                .modifier(CentredUnderTheDoor(
                    offCentre: offCentre,
                    safeWidth: safeWidth,
                    minimumWidth: Self.minimumWidthUnderTheDoor,
                ))
                .frame(maxWidth: .infinity)
                .frame(height: split.after)
        }
    }

    /// Where the glow behind the door is centred on a screen whose frame is `screen`: behind the door.
    private func glowCentre(on screen: CGRect) -> UnitPoint {
        switch Fold(crease?.split(screen)) {
        case let .book(split):
            UnitPoint(x: split.before / 2 / screen.width, y: 1 / 3)
        case let .tabletop(split):
            UnitPoint(x: 0.5, y: split.before / 3 / screen.height)
        case nil:
            UnitPoint(x: 0.5, y: 1 / 3)
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
    private func background(glowCentre: UnitPoint) -> some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(
                colors: [Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14), .clear],
                center: glowCentre,
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

/// How the lock screen is laid out around a crease, if there's one with room for it on both sides.
private enum Fold {
    /// Open like a book, with a vertical crease.
    case book(CreaseSplit)
    /// Stood on a table, with a horizontal crease.
    case tabletop(CreaseSplit)

    init?(_ split: CreaseSplit?) {
        guard let split else { return nil }
        switch split.axis {
        // Each page holds a line of words, or the Unlock button, at a readable width.
        case .vertical where min(split.before, split.after) >= 200:
            self = .book(split)
        // The top half holds the door with room around it. The keyboard can leave the bottom half short.
        case .horizontal where split.before >= 160:
            self = .tabletop(split)
        default:
            return nil
        }
    }
}

extension AppLockBackdrop where Details == EmptyView, Action == EmptyView {
    /// The door alone.
    init() {
        self.init(details: { EmptyView() }, action: { EmptyView() })
    }
}
