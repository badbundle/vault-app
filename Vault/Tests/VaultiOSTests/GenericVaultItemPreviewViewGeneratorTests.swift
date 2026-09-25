import Foundation
import FoundationExtensions
import SwiftUI
import TestHelpers
import Testing
import VaultCore
import VaultFeed
@testable import VaultiOS

@MainActor
final class GenericVaultItemPreviewViewGeneratorTests {
    @Test
    func init_hasNoSideEffects() {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        _ = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        #expect(totp.calledMethods == [])
        #expect(hotp.calledMethods == [])
        #expect(note.calledMethods == [])
        #expect(encrypted.calledMethods == [])
    }

    @Test
    func makeVaultPreviewView_makesTOTPViewForTOTP() {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        let sut = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        let code = OTPAuthCode(type: .totp(), data: .init(secret: .empty(), accountName: "Any"))
        let view = sut.makeVaultPreviewView(item: .otpCode(code), metadata: uniqueMetadata(), behaviour: .normal)

        assertSnapshot(of: view.frame(width: 100, height: 100), as: .image)
    }

    @Test
    func makeVaultPreviewView_makesHOTPViewForHOTP() {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        let sut = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        let code = OTPAuthCode(type: .hotp(), data: .init(secret: .empty(), accountName: "Any"))
        let view = sut.makeVaultPreviewView(item: .otpCode(code), metadata: uniqueMetadata(), behaviour: .normal)

        assertSnapshot(of: view.frame(width: 100, height: 100), as: .image)
    }

    @Test
    func makeVaultPreviewView_makesSecureNoteView() {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        let sut = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        let noteItem = SecureNote(title: "Title", contents: "Contents", format: .markdown)
        let view = sut.makeVaultPreviewView(item: .secureNote(noteItem), metadata: uniqueMetadata(), behaviour: .normal)

        assertSnapshot(of: view.frame(width: 100, height: 100), as: .image)
    }

    @Test
    func makeVaultPreviewView_makesEncryptedItemView() {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        let sut = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        let encryptedItem = EncryptedItem(
            version: "1.0.0",
            title: "Hello, there!",
            data: .random(count: 10),
            authentication: .random(count: 10),
            encryptionIV: .random(count: 10),
            keygenSalt: .random(count: 10),
            keygenSignature: "any",
        )
        let view = sut.makeVaultPreviewView(
            item: .encryptedItem(encryptedItem),
            metadata: uniqueMetadata(),
            behaviour: .normal,
        )

        assertSnapshot(of: view.frame(width: 100, height: 100), as: .image)
    }

    /// Recovery phrases are only stored encrypted, so this is a fallback that must not reveal anything.
    @Test
    func makeVaultPreviewView_recoveryPhraseShowsHiddenEncryptedTile() {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        let sut = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        let phrase = RecoveryPhrase(title: "Secret title", words: ["abandon"], standard: .bip39, passphrase: "")
        let view = sut.makeVaultPreviewView(
            item: .recoveryPhrase(phrase),
            metadata: uniqueMetadata(),
            behaviour: .normal,
        )

        assertSnapshot(of: view.frame(width: 150, height: 150), as: .image)
        #expect(totp.calledMethods == [])
        #expect(hotp.calledMethods == [])
        #expect(note.calledMethods == [])
        #expect(encrypted.calledMethods == [])
    }

    @Test
    func scenePhaseDidChange_callsOnAllCollaborators() {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        let sut = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        sut.scenePhaseDidChange(to: .active)

        #expect(totp.calledMethods == ["scenePhaseDidChange(to:)"])
        #expect(hotp.calledMethods == ["scenePhaseDidChange(to:)"])
        #expect(note.calledMethods == ["scenePhaseDidChange(to:)"])
        #expect(encrypted.calledMethods == ["scenePhaseDidChange(to:)"])
    }

    @Test
    func clearViewCache_callsOnAllCollaborators() async {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        let sut = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        await sut.clearViewCache()

        #expect(totp.calledMethods == ["clearViewCache()"])
        #expect(hotp.calledMethods == ["clearViewCache()"])
        #expect(note.calledMethods == ["clearViewCache()"])
        #expect(encrypted.calledMethods == ["clearViewCache()"])
    }

    @Test
    func didAppear_callsOnAllCollaborators() {
        let totp = TOTPGeneratorMock()
        let hotp = HOTPGeneratorMock()
        let note = SecureNoteGeneratorMock()
        let encrypted = EncryptedItemGeneratorMock()
        let sut = makeSUT(totp: totp, hotp: hotp, secureNote: note, encryptedItem: encrypted)

        sut.didAppear()

        #expect(totp.calledMethods == ["didAppear()"])
        #expect(hotp.calledMethods == ["didAppear()"])
        #expect(note.calledMethods == ["didAppear()"])
        #expect(encrypted.calledMethods == ["didAppear()"])
    }
}

// MARK: - Helpers

extension GenericVaultItemPreviewViewGeneratorTests {
    private typealias SUT = GenericVaultItemPreviewViewGenerator<
        TOTPGeneratorMock,
        HOTPGeneratorMock,
        SecureNoteGeneratorMock,
        EncryptedItemGeneratorMock,
    >
    @MainActor
    private func makeSUT(
        totp: TOTPGeneratorMock,
        hotp: HOTPGeneratorMock,
        secureNote: SecureNoteGeneratorMock,
        encryptedItem: EncryptedItemGeneratorMock,
    ) -> SUT {
        GenericVaultItemPreviewViewGenerator(
            totpGenerator: totp,
            hotpGenerator: hotp,
            noteGenerator: secureNote,
            encryptedGenerator: encryptedItem,
        )
    }
}

// MARK: - Mocks

private class HOTPGeneratorMock: VaultItemPreviewViewGenerator {
    typealias PreviewItem = HOTPAuthCode
    private(set) var calledMethods = [String]()

    @MainActor
    init() {}

    func makeVaultPreviewView(
        item _: PreviewItem,
        metadata _: VaultItem.Metadata,
        behaviour _: VaultItemViewBehaviour,
    ) -> some View {
        Text("HOTP")
    }

    func clearViewCache() async {
        calledMethods.append(#function)
    }

    func scenePhaseDidChange(to _: ScenePhase) {
        calledMethods.append(#function)
    }

    func didAppear() {
        calledMethods.append(#function)
    }
}

private class TOTPGeneratorMock: VaultItemPreviewViewGenerator {
    typealias PreviewItem = TOTPAuthCode
    private(set) var calledMethods = [String]()

    @MainActor
    init() {}

    func makeVaultPreviewView(
        item _: PreviewItem,
        metadata _: VaultItem.Metadata,
        behaviour _: VaultItemViewBehaviour,
    ) -> some View {
        Text("TOTP")
    }

    func clearViewCache() async {
        calledMethods.append(#function)
    }

    func scenePhaseDidChange(to _: ScenePhase) {
        calledMethods.append(#function)
    }

    func didAppear() {
        calledMethods.append(#function)
    }
}

private class SecureNoteGeneratorMock: VaultItemPreviewViewGenerator {
    typealias PreviewItem = SecureNote
    private(set) var calledMethods = [String]()

    @MainActor
    init() {}

    func makeVaultPreviewView(
        item _: SecureNote,
        metadata _: VaultItem.Metadata,
        behaviour _: VaultItemViewBehaviour,
    ) -> some View {
        Text("Secure Note")
    }

    func clearViewCache() async {
        calledMethods.append(#function)
    }

    func scenePhaseDidChange(to _: ScenePhase) {
        calledMethods.append(#function)
    }

    func didAppear() {
        calledMethods.append(#function)
    }
}

private class EncryptedItemGeneratorMock: VaultItemPreviewViewGenerator {
    typealias PreviewItem = EncryptedItem
    private(set) var calledMethods = [String]()

    @MainActor
    init() {}

    func makeVaultPreviewView(
        item _: EncryptedItem,
        metadata _: VaultItem.Metadata,
        behaviour _: VaultItemViewBehaviour,
    ) -> some View {
        Text("Encrypted Item")
    }

    func clearViewCache() async {
        calledMethods.append(#function)
    }

    func scenePhaseDidChange(to _: ScenePhase) {
        calledMethods.append(#function)
    }

    func didAppear() {
        calledMethods.append(#function)
    }
}
