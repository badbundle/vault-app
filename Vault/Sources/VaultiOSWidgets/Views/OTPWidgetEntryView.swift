import SwiftUI
import WidgetKit

/// Top-level widget view that dispatches to the right per-family layout.
public struct OTPWidgetEntryView: View {
    #if !os(macOS)
    @Environment(\.widgetFamily) private var family
    #endif

    public var entry: OTPWidgetEntry

    public init(entry: OTPWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        #if os(macOS)
        // The Mac's widget comes in the small size only (`OTPWidget.families`).
        OTPWidgetSmallView(snapshot: entry.snapshot)
        #else
        switch family {
        case .systemSmall:
            OTPWidgetSmallView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            OTPWidgetAccessoryRectangularView(snapshot: entry.snapshot)
        case .accessoryCircular:
            OTPWidgetAccessoryCircularView(snapshot: entry.snapshot)
        default:
            OTPWidgetSmallView(snapshot: entry.snapshot)
        }
        #endif
    }
}
