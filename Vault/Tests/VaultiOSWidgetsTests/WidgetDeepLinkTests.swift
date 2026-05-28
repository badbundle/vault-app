import Foundation
import Testing
@testable import VaultiOSShared

struct WidgetDeepLinkTests {
    @Test
    func hotpIncrement_roundTripsViaParse() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC").unsafelyUnwrapped
        let url = WidgetDeepLink.hotpIncrement(itemID: id)
        let action = WidgetDeepLink.parse(url)
        #expect(action == .incrementHOTP(itemID: id))
    }

    @Test
    func openItemDetail_roundTripsViaParse() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC").unsafelyUnwrapped
        let url = WidgetDeepLink.openItemDetail(itemID: id)
        let action = WidgetDeepLink.parse(url)
        #expect(action == .openItemDetail(itemID: id))
    }

    @Test
    func parse_returnsNil_forUnknownScheme() {
        let url = URL(string: "https://example.com/otp/abc/increment").unsafelyUnwrapped
        #expect(WidgetDeepLink.parse(url) == nil)
    }

    @Test
    func parse_returnsNil_forUnknownHost() {
        let url = URL(string: "vault://settings/foo").unsafelyUnwrapped
        #expect(WidgetDeepLink.parse(url) == nil)
    }

    @Test
    func parse_returnsNil_forUnknownAction() {
        let url = URL(string: "vault://otp/12345678-1234-1234-1234-123456789ABC/delete").unsafelyUnwrapped
        #expect(WidgetDeepLink.parse(url) == nil)
    }

    @Test
    func parse_returnsNil_forMissingItemID() {
        let url = URL(string: "vault://otp/increment").unsafelyUnwrapped
        #expect(WidgetDeepLink.parse(url) == nil)
    }

    @Test
    func parse_returnsNil_forMalformedUUID() {
        let url = URL(string: "vault://otp/not-a-uuid/increment").unsafelyUnwrapped
        #expect(WidgetDeepLink.parse(url) == nil)
    }

    @Test
    func parse_returnsNil_forMalformedDetailUUID() {
        let url = URL(string: "vault://otp/not-a-uuid/detail").unsafelyUnwrapped
        #expect(WidgetDeepLink.parse(url) == nil)
    }
}
