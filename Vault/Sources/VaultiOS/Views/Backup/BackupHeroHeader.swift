import Foundation
import SwiftUI

/// Centered headline for a backup screen: a large symbol, a title, a subtitle and an optional
/// accessory underneath.
///
/// Sits in its own `Form` section without a row background, so it reads as the screen's headline
/// rather than as another row.
struct BackupHeroHeader<Accessory: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var color: Color
    /// Point size of the symbol at the default Dynamic Type size.
    var iconSize: Double
    /// Bounces the symbol once when the header first appears, to celebrate a finished step.
    var bouncesOnAppear: Bool
    @ViewBuilder var accessory: () -> Accessory

    @ScaledMetric(relativeTo: .largeTitle) private var iconScale: Double = 1
    @State private var hasAppeared = false

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        iconSize: Double = 72,
        bouncesOnAppear: Bool = false,
        @ViewBuilder accessory: @escaping () -> Accessory,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.color = color
        self.iconSize = iconSize
        self.bouncesOnAppear = bouncesOnAppear
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize * iconScale))
                .foregroundStyle(color)
                .symbolEffect(.bounce, value: hasAppeared)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            accessory()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .noListBackground()
        .onAppear {
            if bouncesOnAppear {
                hasAppeared = true
            }
        }
    }
}

extension BackupHeroHeader where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        iconSize: Double = 72,
        bouncesOnAppear: Bool = false,
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            color: color,
            iconSize: iconSize,
            bouncesOnAppear: bouncesOnAppear,
        ) {
            EmptyView()
        }
    }
}

#Preview {
    Form {
        Section {
            BackupHeroHeader(
                title: "Backup Password Set",
                subtitle: "Your backups will be encrypted with this password from now on.",
                systemImage: "checkmark.shield.fill",
                color: .green,
                bouncesOnAppear: true,
            )
        }
        Section {
            BackupHeroHeader(
                title: "Change Backup Password",
                subtitle: "Backups are encrypted with this password.",
                systemImage: "lock.shield.fill",
                color: .accentColor,
                iconSize: 56,
            ) {
                Label("Current password set today", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
            }
        }
    }
}
