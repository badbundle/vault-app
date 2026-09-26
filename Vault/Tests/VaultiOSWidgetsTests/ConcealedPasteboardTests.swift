import Foundation
import Testing
import UIKit
@testable import VaultiOSShared

struct ConcealedPasteboardTests {
    @Test
    func items_markTheValueConcealed() throws {
        let items = ConcealedPasteboard.items(for: "123456")

        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item[UIPasteboard.typeAutomatic] as? String == "123456")
        #expect(item["org.nspasteboard.ConcealedType"] as? String == "123456")
    }

    @Test(arguments: [false, true])
    func options_keepToThisDeviceAsAsked(localOnly: Bool) {
        let options = ConcealedPasteboard.options(expiresAt: nil, localOnly: localOnly)

        #expect(options[.localOnly] as? Bool == localOnly)
    }

    @Test
    func options_expireWhenAsked() {
        let expiresAt = Date(timeIntervalSince1970: 1_000_060)

        let options = ConcealedPasteboard.options(expiresAt: expiresAt, localOnly: true)

        #expect(options[.expirationDate] as? Date == expiresAt)
    }

    @Test
    func options_neverExpireWithoutADate() {
        let options = ConcealedPasteboard.options(expiresAt: nil, localOnly: true)

        #expect(options[.expirationDate] == nil)
    }
}
