import Foundation
import SwiftUI
import VaultSettings

/// What tapping a `FormActionRow` does, which decides its trailing edge and the color of its title.
enum FormActionRowKind {
    /// It happens here, on this screen: no chevron, and the title is tinted, as a form's buttons are.
    case action
    /// It opens another screen, sheet or picker: a chevron, and the title is in the label color, as on a row that
    /// navigates.
    case disclosure
    /// It leaves Vault, for the App Store or a website: an arrow pointing up and out.
    case external
}

/// The one way a `Form` offers an action: a row with a leading icon tile, like the rows that navigate.
///
/// Every button in a form is one of these, so a page's actions line up with its other rows rather than competing
/// with them. `FormActionRowKind` says what the tap does. A `.destructive` role makes the tile and the title red.
/// While the action runs, a spinner takes the trailing edge, and the row can't be tapped again.
///
/// For a `Link`, `ShareLink` or `NavigationLink`, or a button with an icon that isn't a symbol, use
/// `FormActionRowLabel` as the label.
struct FormActionRow: View {
    var title: String
    var subtitle: String?
    var value: String?
    var systemImage: String
    var color: Color
    var kind: FormActionRowKind
    var role: ButtonRole?
    /// Shows the spinner for work the row's own action doesn't wait for, such as what a confirmation starts.
    var isLoading: Bool
    var actionOptions: Set<AsyncButtonActionOption>
    var action: () async throws -> Void

    init(
        _ title: String,
        subtitle: String? = nil,
        value: String? = nil,
        systemImage: String,
        color: Color = .accentColor,
        kind: FormActionRowKind = .action,
        role: ButtonRole? = nil,
        isLoading: Bool = false,
        actionOptions: Set<AsyncButtonActionOption> = Set(AsyncButtonActionOption.allCases),
        action: @escaping () async throws -> Void,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.systemImage = systemImage
        self.color = color
        self.kind = kind
        self.role = role
        self.isLoading = isLoading
        self.actionOptions = actionOptions
        self.action = action
    }

    var body: some View {
        AsyncButton(
            role: role,
            action: action,
            actionOptions: actionOptions,
            label: {
                label(isLoading: isLoading)
            },
            loading: {
                label(isLoading: true)
            },
        )
    }

    private func label(isLoading: Bool) -> some View {
        FormActionRowLabel(
            title,
            subtitle: subtitle,
            value: value,
            systemImage: systemImage,
            color: color,
            kind: kind,
            isDestructive: role == .destructive,
            isLoading: isLoading,
        )
    }
}

/// The label of a `FormActionRow`, for a `Link`, `ShareLink` or `NavigationLink`, or a `Button` that needs an icon of
/// its own.
struct FormActionRowLabel<Icon: View>: View {
    var title: String
    var subtitle: String?
    /// The setting's current value, on the trailing edge before the chevron.
    var value: String?
    var color: Color
    var kind: FormActionRowKind
    var isDestructive: Bool
    var isLoading: Bool
    var icon: Icon

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        subtitle: String? = nil,
        value: String? = nil,
        color: Color = .accentColor,
        kind: FormActionRowKind = .action,
        isDestructive: Bool = false,
        isLoading: Bool = false,
        @ViewBuilder icon: () -> Icon,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.color = color
        self.kind = kind
        self.isDestructive = isDestructive
        self.isLoading = isLoading
        self.icon = icon()
    }

    init(
        _ title: String,
        subtitle: String? = nil,
        value: String? = nil,
        systemImage: String,
        color: Color = .accentColor,
        kind: FormActionRowKind = .action,
        isDestructive: Bool = false,
        isLoading: Bool = false,
    ) where Icon == Image {
        self.init(
            title,
            subtitle: subtitle,
            value: value,
            color: color,
            kind: kind,
            isDestructive: isDestructive,
            isLoading: isLoading,
        ) {
            Image(systemName: systemImage)
        }
    }

    var body: some View {
        FormRow(color: tileColor) {
            icon
        } content: {
            if let value {
                // The value stays on the trailing edge while a long title wraps, as in Settings.
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(value)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                        accessory
                    }
                } label: {
                    text
                }
            } else {
                HStack {
                    text
                    Spacer(minLength: 8)
                    accessory
                }
            }
        }
        // The whole row is the target, not just its text.
        .contentShape(.rect)
    }

    private var text: some View {
        VStack(alignment: .leading) {
            Text(title)
                // Explicit, so a button or a link doesn't tint a title that shouldn't be.
                .foregroundStyle(titleStyle)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var accessory: some View {
        if isLoading {
            ProgressView()
        } else {
            switch kind {
            case .action:
                EmptyView()
            case .disclosure:
                accessorySymbol("chevron.forward")
            case .external:
                accessorySymbol("arrow.up.right")
            }
        }
    }

    private func accessorySymbol(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(uiColor: .tertiaryLabel))
            .accessibilityHidden(true)
    }

    private var hue: Color {
        isDestructive ? .red : color
    }

    /// Faded while the row can't be tapped, as the title is.
    private var tileColor: Color {
        isEnabled ? hue : hue.opacity(0.4)
    }

    private var titleStyle: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(Color(uiColor: .tertiaryLabel)) }
        if isDestructive {
            return AnyShapeStyle(Color.red)
        }
        switch kind {
        case .action: return AnyShapeStyle(.tint)
        case .disclosure, .external: return AnyShapeStyle(Color(uiColor: .label))
        }
    }
}

#Preview {
    Form {
        Section {
            FormActionRow("Authenticate", systemImage: "key.horizontal.fill") {}
            FormActionRow("Slow", systemImage: "clock") {
                try await Task.sleep(for: .seconds(3))
            }
            FormActionRow("Decrypt", systemImage: "lock.open.fill") {}
                .disabled(true)
            FormActionRow("Erasing", systemImage: "trash.fill", role: .destructive, isLoading: true) {}
        } header: {
            Text("Acts here")
        }
        Section {
            FormActionRow(
                "PDF Backup",
                subtitle: "An encrypted file you can save or print.",
                systemImage: "doc.text.fill",
                kind: .disclosure,
            ) {}
            FormActionRow("Save To", value: "Vault Backups", systemImage: "icloud", color: .blue, kind: .disclosure) {}
            FormActionRow(
                "Import & Override",
                systemImage: "exclamationmark.triangle.fill",
                kind: .disclosure,
                role: .destructive,
            ) {}
        } header: {
            Text("Opens something")
        }
        Section {
            Link(destination: VaultAppStore.writeReviewURL) {
                FormActionRowLabel("Rate Vault", systemImage: "star.fill", color: .orange, kind: .external)
            }
        } header: {
            Text("Leaves Vault")
        }
    }
}
