import Foundation
import Testing
import VaultCore
@testable import VaultFeed
@testable import VaultMac

struct VaultMacEditorTests {
    @Test
    func codeScanned_otpauthURI_isTheCode() throws {
        let code = try #require(VaultMacCodeEditor.code(
            scanned: "otpauth://totp/Example:ada@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=6&period=30",
        ))

        #expect(code.data.issuer == "Example")
        #expect(code.data.accountName == "ada@example.com")
        #expect(code.type == .totp(period: 30))
    }

    @Test(arguments: ["https://example.com", "not a code", "otpauth://unknown/Example?secret=JBSWY3DPEHPK3PXP"])
    func codeScanned_anythingElse_isNothing(text: String) {
        #expect(VaultMacCodeEditor.code(scanned: text) == nil)
    }

    @Test
    func newPassword_onlyCountsOnceConfirmed() {
        var sut = VaultMacNewPassword()
        #expect(sut.confirmed.isEmpty)
        #expect(sut.agrees)

        sut.password = "correct horse"
        #expect(sut.confirmed.isEmpty)
        #expect(!sut.agrees)

        sut.confirmation = "correct hors"
        #expect(sut.confirmed.isEmpty)
        #expect(!sut.agrees)

        sut.confirmation = "correct horse"
        #expect(sut.confirmed == "correct horse")
        #expect(sut.agrees)
    }

    @Test
    func editorRequest_newItems_eachHaveTheirOwnID() {
        let ids: Set = [
            VaultMacEditorRequest.newCode.id,
            VaultMacEditorRequest.newNote.id,
            VaultMacEditorRequest.newRecoveryPhrase.id,
        ]

        #expect(ids.count == 3)
    }

    @Test
    func editorRequest_existingItem_isIdentifiedByTheItem() {
        let item = MacTestItems.note()
        guard case let .secureNote(note) = item.item else { return }

        #expect(VaultMacEditorRequest.editNote(note, item.metadata, nil).id == item.metadata.id.id.uuidString)
    }
}
