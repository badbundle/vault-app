import SwiftUI
import WidgetKit

/// The OTP code widget. Embed in a `WidgetBundle` inside the widget
/// extension target:
///
/// ```swift
/// @main
/// struct VaultWidgetsBundle: WidgetBundle {
///     var body: some Widget { OTPWidget() }
/// }
/// ```
///
/// The iOS and Mac widget extensions both embed it. The Mac's has the small
/// size only: the Lock Screen's sizes aren't on the Mac.
public struct OTPWidget: Widget {
    /// Stable kind identifier used by `WidgetCenter` to reload timelines.
    public nonisolated static let kind = "com.badbundle.vault.OTPWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: OTPWidgetIntent.self,
            provider: OTPWidgetProvider(),
        ) { entry in
            OTPWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("OTP Code")
        .description("Show a one-time code from your vault.")
        .supportedFamilies(Self.families)
    }

    #if os(macOS)
    static let families: [WidgetFamily] = [.systemSmall]
    #else
    static let families: [WidgetFamily] = [
        .systemSmall,
        .accessoryRectangular,
        .accessoryCircular,
    ]
    #endif
}
