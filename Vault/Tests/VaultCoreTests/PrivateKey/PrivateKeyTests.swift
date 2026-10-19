import Foundation
import Testing
import VaultCore

struct PrivateKeyTests {
    private let sut = PrivateKey(
        title: "My title",
        key: PrivateKeyTestFixtures.wifCompressed,
        contents: "The secret description",
    )

    /// The key and description never reach a log, a crash report or a test's failure message through interpolation.
    @Test
    func description_isRedacted() {
        for text in ["\(sut)", String(describing: sut), String(reflecting: sut), sut.debugDescription] {
            #expect(!text.contains(PrivateKeyTestFixtures.wifCompressed))
            #expect(!text.contains("secret"))
            #expect(text.contains("redacted"))
        }
    }

    @Test
    func mirror_hasNoChildren() {
        #expect(Mirror(reflecting: sut).children.isEmpty)
    }
}
