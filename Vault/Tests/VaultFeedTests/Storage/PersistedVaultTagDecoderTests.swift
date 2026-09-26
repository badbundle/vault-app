import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

struct PersistedVaultTagDecoderTests {}

// MARK: - Fields

extension PersistedVaultTagDecoderTests {
    @Test
    func decode_id() throws {
        let id = UUID()
        let item = makeRecord(id: id)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.id.id == id)
    }

    @Test
    func decode_name() throws {
        let name = "my tag name"
        let item = makeRecord(title: name)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.name == name)
    }

    @Test
    func decode_colorNilIsTagDefault() throws {
        let item = makeRecord(color: nil)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.color == .tagDefault)
    }

    @Test
    func decode_colorWithValues() throws {
        let color = PersistedColor(red: 0.5, green: 0.6, blue: 0.7)
        let item = makeRecord(color: color)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.color.red == 0.5)
        #expect(decoded.color.green == 0.6)
        #expect(decoded.color.blue == 0.7)
    }

    @Test
    func decode_iconName() throws {
        let iconName = "my icon name"
        let item = makeRecord(iconName: iconName)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.iconName == iconName)
    }

    @Test
    func decode_iconNameNilIsDefault() throws {
        let item = makeRecord(iconName: nil)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.iconName == VaultItemTag.defaultIconName)
    }
}

// MARK: - Helpers

extension PersistedVaultTagDecoderTests {
    private func makeSUT() -> PersistedVaultTagDecoder {
        PersistedVaultTagDecoder()
    }

    private func makeRecord(
        id: UUID = UUID(),
        title: String = "Any",
        color: PersistedColor? = nil,
        iconName: String? = nil,
    ) -> VaultTagRecord {
        VaultTagRecord(id: id, title: title, color: color, iconName: iconName)
    }
}
