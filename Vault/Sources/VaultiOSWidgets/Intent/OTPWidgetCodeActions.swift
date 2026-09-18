import AppIntents
import Foundation
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

public struct CopyTOTPCodeIntent: AppIntent {
    public nonisolated static let title: LocalizedStringResource = "Copy Code"
    public nonisolated static let openAppWhenRun = false

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

        WidgetPasteboard.copyOTP(code)
        return .result()
    }
}

public struct IncrementAndCopyHOTPCodeIntent: AppIntent {
    public nonisolated static let title: LocalizedStringResource = "Next Code"
    public nonisolated static let openAppWhenRun = false

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

        WidgetPasteboard.copyOTP(code)
        WidgetCenter.shared.reloadTimelines(ofKind: OTPWidget.kind)
        return .result()
    }
}

enum WidgetPasteboard {
    private static let concealedTypeIdentifier = "org.nspasteboard.ConcealedType"

    static func copyOTP(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.setItems([[
            UIPasteboard.typeAutomatic: string,
            concealedTypeIdentifier: string,
        ]], options: [.localOnly: true])
        #endif
    }
}
