import Foundation
import UIKit
import VaultFeed
import VaultiOSShared
import VaultSettings

/// @mockable
public protocol SystemPasteboard {
    /// Copy the given string to the pasteboard.
    ///
    /// - Parameters:
    ///   - string: The value to copy.
    ///   - ttl: How long the item should live in the pasteboard. `nil` means no expiry.
    ///   - localOnly: When `true`, the item is not pushed to iCloud Universal Clipboard.
    func copy(string: String, ttl: Double?, localOnly: Bool)
}

/// The live iOS system pasteboard.
struct SystemPasteboardImpl: SystemPasteboard {
    private let clock: any EpochClock

    init(clock: any EpochClock) {
        self.clock = clock
    }

    func copy(string: String, ttl: Double?, localOnly: Bool) {
        let now = Date(timeIntervalSince1970: clock.currentTime)
        ConcealedPasteboard.copy(string, expiresAt: ttl.map { now.addingTimeInterval($0) }, localOnly: localOnly)
    }
}
