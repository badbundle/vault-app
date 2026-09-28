import AppIntents
import Foundation
import FoundationExtensions
import VaultFeed
import VaultiOSShared
import VaultSettings
import WidgetKit

/// Copies a time-based code from the widget. In StandBy, or anywhere else the widget can be seen while the iPhone is
/// locked, it asks for the iPhone to be unlocked first.
public struct CopyTOTPCodeIntent: AppIntent {
    public nonisolated static let title: LocalizedStringResource = "Copy Code"
    public nonisolated static let openAppWhenRun = false
    public nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

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
              let code = try await WidgetVaultLoader.shared.currentTOTPCode(id: id)
        else {
            return .result()
        }

        await WidgetPasteboard.copyOTP(code)
        return .result()
    }
}

/// Advances a counter-based code and copies the next one from the widget. Like copying a time-based code, it asks for
/// the iPhone to be unlocked first.
public struct IncrementAndCopyHOTPCodeIntent: AppIntent {
    public nonisolated static let title: LocalizedStringResource = "Next Code"
    public nonisolated static let openAppWhenRun = false
    public nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

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
              let code = try await WidgetVaultLoader.shared.incrementAndRenderHOTPCode(id: id)
        else {
            return .result()
        }

        await WidgetPasteboard.copyOTP(code)
        WidgetCenter.shared.reloadTimelines(ofKind: OTPWidget.kind)
        return .result()
    }
}

enum WidgetPasteboard {
    /// Copies a code as the app does: concealed, and cleared after the Clear Clipboard time chosen in the app, which
    /// keeps it in the defaults it shares with the widget. It always stays on this device, whatever Universal Clipboard
    /// allows.
    @MainActor
    static func copyOTP(
        _ code: String,
        settings: Defaults = Defaults(userDefaults: VaultSharedStorage.userDefaults()),
        now: Date = Date(),
        write: (_ string: String, _ expiresAt: Date?, _ localOnly: Bool) -> Void = { string, expiresAt, localOnly in
            #if canImport(UIKit)
            ConcealedPasteboard.copy(string, expiresAt: expiresAt, localOnly: localOnly)
            #endif
        },
    ) {
        let expiresAt = PasteTTL.stored(in: settings).expiryDate(copiedAt: now)
        write(code, expiresAt, true)
    }
}
