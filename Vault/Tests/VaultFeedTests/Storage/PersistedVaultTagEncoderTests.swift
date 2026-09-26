import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

struct PersistedVaultTagEncoderTests {}

// MARK: - Encoding

extension PersistedVaultTagEncoderTests {
    @Test
    func encode_newItemCreatedUUID() {
        let sut = makeSUT()

        var seenIds = Set<UUID>()
        for _ in 1 ... 100 {
            let item = makeWritableVaultItemTag()
            let encoded = sut.encode(tag: item)
            seenIds.insert(encoded.id)
        }
        #expect(seenIds.count == 100)
    }

    @Test
    func encode_name() {
        let name = "my tag name"
        let sut = makeSUT()
        let item = makeWritableVaultItemTag(name: name)

        let encoded = sut.encode(tag: item)

        #expect(encoded.title == name)
    }

    @Test
    func encode_colorWithValues() {
        let sut = makeSUT()
        let color = VaultItemColor(red: 0.5, green: 0.6, blue: 0.7)
        let item = makeWritableVaultItemTag(color: color)

        let encoded = sut.encode(tag: item)

        #expect(encoded.color == PersistedColor(red: 0.5, green: 0.6, blue: 0.7))
    }

    @Test
    func encode_iconName() {
        let name = "my icon name"
        let sut = makeSUT()
        let item = makeWritableVaultItemTag(iconName: name)

        let encoded = sut.encode(tag: item)

        #expect(encoded.iconName == name)
    }

    @Test
    func encode_existingTagKeepsIDAndReplacesFields() {
        let sut = makeSUT()
        let existing = VaultTagRecord(
            id: UUID(),
            title: "Before",
            color: PersistedColor(red: 0.1, green: 0.2, blue: 0.3),
            iconName: "before.icon",
        )
        let item = makeWritableVaultItemTag(
            name: "After",
            color: VaultItemColor(red: 0.4, green: 0.5, blue: 0.6),
            iconName: "after.icon",
        )

        let encoded = sut.encode(tag: item, existing: existing)

        #expect(encoded == VaultTagRecord(
            id: existing.id,
            title: "After",
            color: PersistedColor(red: 0.4, green: 0.5, blue: 0.6),
            iconName: "after.icon",
        ))
    }

    @Test
    func encode_importingUsesContextID() {
        let sut = makeSUT()
        let id = Identifier<VaultItemTag>(id: UUID())
        let item = makeWritableVaultItemTag(name: "Imported")

        let encoded = sut.encode(tag: item, writeUpdateContext: .init(id: id))

        #expect(encoded.id == id.id)
        #expect(encoded.title == "Imported")
    }
}

// MARK: - Helpers

extension PersistedVaultTagEncoderTests {
    private func makeSUT() -> PersistedVaultTagEncoder {
        PersistedVaultTagEncoder()
    }

    private func makeWritableVaultItemTag(
        name: String = "Any",
        color: VaultItemColor = .tagDefault,
        iconName: String = VaultItemTag.defaultIconName,
    ) -> VaultItemTag.Write {
        .init(
            name: name,
            color: color,
            iconName: iconName,
        )
    }
}
