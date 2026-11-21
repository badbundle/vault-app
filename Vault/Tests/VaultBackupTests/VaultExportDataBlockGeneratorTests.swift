import Foundation
import TestHelpers
import Testing
@testable import VaultBackup

struct VaultExportDataBlockGeneratorTests {
    @Test
    func makeDocument_createsExpectedContent() throws {
        let sut = VaultExportDataBlockGenerator(payload: .init(
            encryptedVault: .init(
                version: "1.0.0",
                data: Data(),
                authentication: Data(),
                encryptionIV: Data(),
                keygenSalt: Data(),
                keygenSignature: "my-signature",
            ),
            userDescription: "my desc",
            created: Date(),
        ))

        let document = try sut.makeDocument(knownPageCount: 2)

        #expect(document.content.map(\.debugDescription) == [
            "TITLE: Vault Export",
            "FIGURE: Seal C7NN-T8YG",
            "TITLE: my desc",
            "TITLE: Your backup is contained within the following QR codes in an encrypted format. To import this backup, you should open the Vault app and scan every code during the import. In this export, there are 1 QR codes.",
            "DATA BLOCK: count:1",
        ])
    }

    @Test
    func makeDocument_splitsUserDescription() throws {
        let description = """
        This is my description
        It's very long

        I think everyone is lame



        nice
        """
        let sut = VaultExportDataBlockGenerator(payload: .init(
            encryptedVault: .init(
                version: "1.0.0",
                data: Data(),
                authentication: Data(),
                encryptionIV: Data(),
                keygenSalt: Data(),
                keygenSignature: "my-signature",
            ),
            userDescription: description,
            created: Date(),
        ))

        let document = try sut.makeDocument(knownPageCount: 2)

        #expect(document.content.map(\.debugDescription) == [
            "TITLE: Vault Export",
            "FIGURE: Seal C7NN-T8YG",
            "TITLE: This is my description",
            "TITLE: It\'s very long",
            "TITLE: I think everyone is lame",
            "TITLE: nice",
            "TITLE: Your backup is contained within the following QR codes in an encrypted format. To import this backup, you should open the Vault app and scan every code during the import. In this export, there are 1 QR codes.",
            "DATA BLOCK: count:1",
        ])
    }

    /// Every page's header carries the seal's code, so a page that comes loose can be matched to its backup.
    @Test
    func makeDocument_headerHasTheSealsCode() throws {
        let sut = VaultExportDataBlockGenerator(payload: .init(
            encryptedVault: .init(
                version: "1.0.0",
                data: Data(),
                authentication: Data(),
                encryptionIV: Data(),
                keygenSalt: Data(),
                keygenSignature: "my-signature",
            ),
            userDescription: "",
            created: Date(timeIntervalSince1970: 3_000_000),
        ))

        let document = try sut.makeDocument(knownPageCount: 2)

        #expect(document.headerGenerator.makeHeader(pageNumber: 2)?.left == "Created 2/4/70, 5:20 PM · Seal C7NN-T8YG")
    }
}
