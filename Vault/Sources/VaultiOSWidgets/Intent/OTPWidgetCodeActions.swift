import AppIntents
import Foundation
import FoundationExtensions
import VaultFeed
import VaultiOSShared
import VaultSettings
import WidgetKit

/// Copies a time-based code from the widget. In StandBy, or anywhere else the widget can be seen while the iPhone is
/// locked, it asks for the iPhone to be unlocked first, as it does for the Mac.
public struct CopyTOTPCodeIntent: AppIntent {
    public nonisolated static let title: LocalizedStringResource = "Copy Code"
    public nonisolated static let openAppWhenRun = false
    public nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    #if os(macOS)
    /// Only the widget runs it: the Mac app offers nothing to Shortcuts or Spotlight (docs/mac-app.md, decision 2).
    public nonisolated static let isDiscoverable = false
    #endif

    @Parameter(title: "Item ID")
    public var itemID: String

    public init() {
        itemID = ""
    }

    public init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID),
              let code = try await OTPWidgetSource.platform.currentTOTPCode(itemID: id, now: Date())
        else {
            return .result()
        }

        await WidgetPasteboard.copyOTP(code)
        return .result()
    }
}

/// Advances a counter-based code and copies the next one from the widget. Like copying a time-based code, it asks for
/// the iPhone to be unlocked first. The Mac's widgets never show a counter-based code, so never run it.
public struct IncrementAndCopyHOTPCodeIntent: AppIntent {
    public nonisolated static let title: LocalizedStringResource = "Next Code"
    public nonisolated static let openAppWhenRun = false
    public nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    #if os(macOS)
    /// Only the widget runs it: the Mac app offers nothing to Shortcuts or Spotlight (docs/mac-app.md, decision 2).
    public nonisolated static let isDiscoverable = false
    #endif

    @Parameter(title: "Item ID")
    public var itemID: String

    public init() {
        itemID = ""
    }

    public init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID),
              let code = try await OTPWidgetSource.platform.incrementAndRenderHOTPCode(itemID: id)
        else {
            return .result()
        }

        await WidgetPasteboard.copyOTP(code)
        WidgetCenter.shared.reloadTimelines(ofKind: OTPWidget.kind)
        return .result()
    }
}

enum WidgetPasteboard {
    #if canImport(UIKit)
    /// Copies a code as the app does: concealed, and cleared after the Clear Clipboard time chosen in the app, which
    /// keeps it in the defaults it shares with the widget. It always stays on this device, whatever Universal Clipboard
    /// allows.
    @MainActor
    static func copyOTP(
        _ code: String,
        settings: Defaults = Defaults(userDefaults: VaultSharedStorage.userDefaults()),
        now: Date = Date(),
        write: (_ string: String, _ expiresAt: Date?, _ localOnly: Bool) -> Void = { string, expiresAt, localOnly in
            ConcealedPasteboard.copy(string, expiresAt: expiresAt, localOnly: localOnly)
        },
    ) {
        let expiresAt = PasteTTL.stored(in: settings).expiryDate(copiedAt: now)
        write(code, expiresAt, true)
    }

    #elseif canImport(AppKit)
    /// Copies a code as the Mac app does (G87): concealed and transient, so clipboard managers neither show nor keep
    /// it, and always kept to this Mac, whatever Universal Clipboard allows, as on iOS.
    ///
    /// AppKit's clipboard has no expiry date, and the widget extension doesn't run long enough to clear it, nor has the
    /// App Group the Clear Clipboard time is kept in. So it leaves the app a note of it (`WidgetCopiedCodeStore`), and
    /// the app clears it as one of its own copies: after the Clear Clipboard time, or when Vault locks or quits.
    @MainActor
    static func copyOTP(
        _ code: String,
        now: Date = Date(),
        notes: WidgetCopiedCodeStore = WidgetCopiedCodeStore(),
        write: (_ string: String, _ localOnly: Bool) -> Int = { string, localOnly in
            ConcealedPasteboard.copy(string, localOnly: localOnly)
        },
    ) {
        let changeCount = write(code, true)
        try? notes.leave(WidgetCopiedCode(changeCount: changeCount, copiedAt: now))
    }
    #endif
}
