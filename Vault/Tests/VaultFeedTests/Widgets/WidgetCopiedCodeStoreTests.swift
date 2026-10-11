import Foundation
import FoundationExtensions
import Security
import Testing
import VaultCore
@testable import VaultFeed

/// The note a Mac widget leaves the app of a code it copied, so the app clears it (G87, G98).
struct WidgetCopiedCodeStoreTests {
    private let copy = WidgetCopiedCode(changeCount: 7, copiedAt: Date(timeIntervalSince1970: 1_800_000_000))

    @Test
    func leave_keepsTheNoteThenTellsTheApp() throws {
        let keychain = InMemoryWidgetKeychainItem()
        let notifiedWithNote = SharedMutex([Bool]())
        let sut = WidgetCopiedCodeStore(keychain: keychain) {
            notifiedWithNote.modify { $0.append(keychain.data != nil) }
        }

        try sut.leave(copy)

        #expect(notifiedWithNote.value == [true])
        #expect(sut.take() == copy)
    }

    /// Each note is taken once.
    @Test
    func take_isGoneOnceTaken() throws {
        let keychain = InMemoryWidgetKeychainItem()
        let sut = WidgetCopiedCodeStore(keychain: keychain, notify: {})
        try sut.leave(copy)

        #expect(sut.take() == copy)
        #expect(sut.take() == nil)
        #expect(keychain.data == nil)
    }

    @Test
    func take_withNoNote_isNothing() {
        let sut = WidgetCopiedCodeStore(keychain: InMemoryWidgetKeychainItem(), notify: {})

        #expect(sut.take() == nil)
    }

    /// Readable once the Mac has been unlocked since it started, so the app can take it as the Mac locks. It holds
    /// nothing of the code.
    @Test
    func note_isReadableAfterTheFirstUnlockAndOnlyOnThisDevice() throws {
        let item = WidgetKeychainItem.copiedCode
        let attributes = item.attributes(for: Data())

        #expect(attributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(item.service == VaultIdentifiers.SecureStorageKey.widgetCopiedCode.keychainService)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(copy)) as? [String: Any])
        #expect(Set(encoded.keys) == ["changeCount", "copiedAt"])
    }
}
