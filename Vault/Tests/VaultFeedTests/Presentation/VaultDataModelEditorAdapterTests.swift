import CryptoEngine
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultFeed

@MainActor
struct VaultDataModelEditorAdapterTests {
    @Test
    func init_hasNoSideEffects() {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        _ = makeSUT(dataModel: dataModel)

        #expect(store.calledMethods == [])
        #expect(tagStore.calledMethods == [])
    }

    @Test
    func createCode_createsOTPCodeInFeed_createsCodeInFeed() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        let sut = makeSUT(dataModel: dataModel)
        let initialCode = OTPAuthCode(
            type: .totp(period: 40),
            data: .init(secret: .empty(), algorithm: .sha256, digits: .default, accountName: "myacc", issuer: "myiss"),
        )
        let initialEdits = OTPCodeDetailEdits(
            hydratedFromCode: initialCode,
            relativeOrder: .min,
            userDescription: "mydesc",
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            tags: [],
            lockState: .notLocked,
            showInQuickType: true,
        )

        try await confirmation("Insert handler called") { confirmation in
            store.insertHandler = { data in
                defer { confirmation() }
                switch data.item {
                case let .otpCode(code):
                    #expect(
                        code == initialCode,
                        "The code that is saved should be the same as the state from the edits",
                    )
                default:
                    Issue.record("invalid kind")
                }
                return .new()
            }

            try await sut.createCode(initialEdits: initialEdits)
        }
    }

    @Test
    func createCode_propagatesFailureOnError() async throws {
        let store = VaultStoreErroring(error: TestError())
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: store)
        let sut = makeSUT(dataModel: dataModel)

        let edits = anyOTPCodeDetailEdits()
        await #expect(throws: (any Error).self) {
            try await sut.createCode(initialEdits: edits)
        }
    }

    @Test
    func updateCode_translatesCodeDataForCall() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await loadDigesters(on: dataModel)
        let sut = makeSUT(dataModel: dataModel)

        var code = uniqueCode()
        code.data.accountName = "old account name"
        code.data.issuer = "old issuer name"
        var item = uniqueVaultItem(item: .otpCode(code))
        item.metadata.userDescription = "old description"
        let color = VaultItemColor(red: 0.0, green: 0.0, blue: 0.0)
        item.metadata.color = color

        var edits = OTPCodeDetailEdits(
            hydratedFromCode: code,
            relativeOrder: .min,
            userDescription: "mydesc",
            color: VaultItemColor(red: 0.5, green: 0.5, blue: 0.5),
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            tags: [],
            lockState: .notLocked,
            showInQuickType: true,
        )
        edits.issuerTitle = "new issuer name"
        edits.accountNameTitle = "new account name"
        edits.description = "new description"
        edits.searchPassphrase = "new pass"
        edits.killphraseEnabled = true
        edits.newKillphrase = "new kill"

        try await confirmation("Update handler called") { confirmation in
            store.updateHandler = { _, data in
                defer { confirmation() }
                #expect(data.userDescription == "new description")
                #expect(data.visibility == .always)
                #expect(data.searchableLevel == .full)
                #expect(data.searchPassphraseUpdate == .clear)
                assertKillphrase(data.killphraseUpdate, matches: "new kill", using: dataModel)
                #expect(data.lockState == .notLocked)
                #expect(data.showInQuickType == true)
                #expect(data.previewMode == .titleAndFirstLine)
                switch data.item {
                case let .otpCode(otpCode):
                    #expect(otpCode.data.accountName == "new account name")
                    #expect(otpCode.data.issuer == "new issuer name")
                case .secureNote, .encryptedItem, .recoveryPhrase:
                    Issue.record("invalid kind")
                }
            }

            try await sut.updateCode(id: item.metadata.id, item: code, edits: edits)
        }
    }

    @Test
    func updateCode_propagatesFailureOnError() async {
        let store = VaultStoreErroring(error: TestError())
        let tagStore = VaultTagStoreErroring(error: TestError())
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        let sut = makeSUT(dataModel: dataModel)

        let edits = anyOTPCodeDetailEdits()
        await #expect(throws: (any Error).self) {
            try await sut.updateCode(
                id: .new(),
                item: uniqueCode(),
                edits: edits,
            )
        }
    }

    @Test
    func deleteCode_deletesFromFeed() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        let sut = makeSUT(dataModel: dataModel)

        let id = Identifier<VaultItem>.new()

        try await confirmation("Delete handler called") { confirmation in
            store.deleteHandler = { actualID in
                defer { confirmation() }
                #expect(id == actualID)
            }

            try await sut.deleteCode(id: id)
        }
    }

    @Test
    func deleteCode_propagatesFailureOnError() async {
        let store = VaultStoreErroring(error: TestError())
        let tagStore = VaultTagStoreErroring(error: TestError())
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        let sut = makeSUT(dataModel: dataModel)

        await #expect(throws: (any Error).self) {
            try await sut.deleteCode(id: .new())
        }
    }

    @Test
    func createNote_createsNote() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await loadDigesters(on: dataModel)
        let sut = makeSUT(dataModel: dataModel)

        var initialEdits = SecureNoteDetailEdits.new()
        initialEdits.contents = "first line\nsecond line"
        initialEdits.viewConfig = .requiresSearchPassphrase
        initialEdits.searchPassphrase = "pass"
        initialEdits.killphraseEnabled = true
        initialEdits.newKillphrase = "this is kill"
        initialEdits.lockState = .lockedWithNativeSecurity

        try await confirmation("Insert handler called") { confirmation in
            store.insertHandler = { data in
                defer { confirmation() }
                #expect(data.userDescription == "second line")
                #expect(data.visibility == .onlySearch)
                #expect(data.searchableLevel == .onlyPassphrase)
                assertSearchPassphrase(data.searchPassphraseUpdate, matches: "pass", using: dataModel)
                assertKillphrase(data.killphraseUpdate, matches: "this is kill", using: dataModel)
                #expect(data.lockState == .lockedWithNativeSecurity)
                #expect(data.previewMode == .titleAndFirstLine)
                switch data.item {
                case let .secureNote(note):
                    #expect(note.title == "first line")
                    #expect(note.contents == "first line\nsecond line")
                default:
                    Issue.record("invalid kind")
                }
                return .new()
            }

            try await sut.createNote(initialEdits: initialEdits)
        }
    }

    @Test
    func createNote_createsEncryptedNoteWithNewPassword() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await loadDigesters(on: dataModel)
        let deriverMock = KeyDeriverMock<KeyData<32>>()
        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.makeVaultItemKeyDeriverHandler = {
            VaultKeyDeriver(deriver: deriverMock, signature: .testing)
        }
        let sut = makeSUT(dataModel: dataModel, keyDeriverFactory: keyDeriverFactory)

        var initialEdits = SecureNoteDetailEdits.new()
        initialEdits.contents = "first line\nsecond line"
        initialEdits.viewConfig = .requiresSearchPassphrase
        initialEdits.searchPassphrase = "pass"
        initialEdits.killphraseEnabled = true
        initialEdits.newKillphrase = "this is kill"
        initialEdits.lockState = .lockedWithNativeSecurity
        initialEdits.newEncryptionPassword = "new password"

        try await confirmation("Insert handler called", expectedCount: 1) { insertConfirmation in
            try await confirmation("Key handler called", expectedCount: 1) { keyConfirmation in
                store.insertHandler = { data in
                    defer { insertConfirmation() }
                    #expect(data.userDescription == "", "Empty because note is encrypted")
                    #expect(data.visibility == .onlySearch)
                    #expect(data.searchableLevel == .onlyPassphrase)
                    assertSearchPassphrase(data.searchPassphraseUpdate, matches: "pass", using: dataModel)
                    assertKillphrase(data.killphraseUpdate, matches: "this is kill", using: dataModel)
                    #expect(data.lockState == .lockedWithNativeSecurity)
                    #expect(data.previewMode == .titleAndFirstLine)
                    switch data.item {
                    case let .encryptedItem(item):
                        #expect(item.title == "first line")
                        #expect(item.keygenSignature == "vault.keygen.testing")
                        #expect(item.data.isNotEmpty)
                        #expect(item.authentication.isNotEmpty)
                        #expect(item.keygenSalt.isNotEmpty)
                        #expect(item.encryptionIV.isNotEmpty)
                    default:
                        Issue.record("invalid kind")
                    }
                    return .new()
                }

                deriverMock.keyHandler = { password, _ in
                    defer { keyConfirmation() }
                    #expect(String(data: password, encoding: .utf8) == "new password")
                    return .random()
                }

                try await sut.createNote(initialEdits: initialEdits)
            }
        }
    }

    @Test
    func createNote_createsEncryptedNoteWithExistingEncryptionKey() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await loadDigesters(on: dataModel)
        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.makeVaultItemKeyDeriverHandler = { .testing }
        let sut = makeSUT(dataModel: dataModel, keyDeriverFactory: keyDeriverFactory)

        var initialEdits = SecureNoteDetailEdits.new()
        initialEdits.contents = "first line\nsecond line"
        initialEdits.viewConfig = .requiresSearchPassphrase
        initialEdits.searchPassphrase = "pass"
        initialEdits.killphraseEnabled = true
        initialEdits.newKillphrase = "this is kill"
        initialEdits.lockState = .lockedWithNativeSecurity
        initialEdits.newEncryptionPassword = ""
        initialEdits.existingEncryptionKey = .init(key: .random(), salt: .random(count: 32), keyDervier: .testing)

        try await confirmation("Insert handler called") { confirmation in
            store.insertHandler = { data in
                defer { confirmation() }
                #expect(data.userDescription == "", "Empty because note is encrypted")
                #expect(data.visibility == .onlySearch)
                #expect(data.searchableLevel == .onlyPassphrase)
                assertSearchPassphrase(data.searchPassphraseUpdate, matches: "pass", using: dataModel)
                assertKillphrase(data.killphraseUpdate, matches: "this is kill", using: dataModel)
                #expect(data.lockState == .lockedWithNativeSecurity)
                #expect(data.previewMode == .titleAndFirstLine)
                switch data.item {
                case let .encryptedItem(item):
                    #expect(item.title == "first line")
                    #expect(item.keygenSignature == "vault.keygen.testing")
                    #expect(item.data.isNotEmpty)
                    #expect(item.authentication.isNotEmpty)
                    #expect(item.keygenSalt.isNotEmpty)
                    #expect(item.encryptionIV.isNotEmpty)
                default:
                    Issue.record("invalid kind")
                }
                return .new()
            }

            try await sut.createNote(initialEdits: initialEdits)
        }
    }

    @Test
    func createNote_propagatesFailureOnError() async throws {
        let store = VaultStoreErroring(error: TestError())
        let tagStore = VaultTagStoreErroring(error: TestError())
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        let sut = makeSUT(dataModel: dataModel)

        await #expect(throws: (any Error).self) {
            try await sut.createNote(initialEdits: .new())
        }
    }

    @Test
    func updateNote_updatesNoteInFeed() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await loadDigesters(on: dataModel)
        let sut = makeSUT(dataModel: dataModel)

        var note = anySecureNote()
        note.title = "old title"
        note.contents = "old contents"
        note.format = .plain
        var item = uniqueVaultItem(item: .secureNote(note))
        item.metadata.userDescription = "old description"

        var edits = SecureNoteDetailEdits.new()
        edits.textFormat = .markdown
        edits.contents = "first line\nsecond line"
        edits.viewConfig = .alwaysVisible
        edits.searchPassphrase = "new pass"
        edits.killphraseEnabled = true
        edits.newKillphrase = "this kill"

        try await confirmation("Update handler called") { confirmation in
            store.updateHandler = { _, data in
                defer { confirmation() }
                #expect(data.userDescription == "second line")
                #expect(data.visibility == .always)
                #expect(data.searchableLevel == .full)
                #expect(data.searchPassphraseUpdate == .clear)
                assertKillphrase(data.killphraseUpdate, matches: "this kill", using: dataModel)
                #expect(data.lockState == .notLocked)
                #expect(data.previewMode == .titleAndFirstLine)
                switch data.item {
                case let .secureNote(note):
                    #expect(note.title == "first line")
                    #expect(note.contents == "first line\nsecond line")
                    #expect(note.format == .markdown)
                default:
                    Issue.record("invalid kind")
                }
            }

            try await sut.updateNote(id: item.metadata.id, item: note, edits: edits)
        }
    }

    @Test
    func updateNote_propagatesFailureOnError() async {
        let store = VaultStoreErroring(error: TestError())
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: store)
        let sut = makeSUT(dataModel: dataModel)

        await #expect(throws: (any Error).self) {
            try await sut.updateNote(id: .new(), item: anySecureNote(), edits: .new())
        }
    }

    @Test
    func deleteNote_deletesFromFeed() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        let sut = makeSUT(dataModel: dataModel)

        let id = Identifier<VaultItem>.new()

        try await confirmation("Delete handler called") { confirmation in
            store.deleteHandler = { actualID in
                defer { confirmation() }
                #expect(id == actualID)
            }

            try await sut.deleteNote(id: id)
        }
    }

    @Test
    func deleteNote_propagatesFailureOnError() async {
        let store = VaultStoreErroring(error: TestError())
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: store)
        let sut = makeSUT(dataModel: dataModel)

        await #expect(throws: (any Error).self) {
            try await sut.deleteNote(id: .new())
        }
    }
}

extension VaultDataModelEditorAdapterTests {
    @MainActor
    private func makeSUT(
        dataModel: VaultDataModel = VaultDataModel(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
            vaultImporter: VaultStoreImporterMock(),
            vaultDeleter: VaultStoreDeleterMock(),
            vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: StubKillphraseKeyStore(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        ),
        keyDeriverFactory: VaultKeyDeriverFactoryMock = VaultKeyDeriverFactoryMock(),
    ) -> VaultDataModelEditorAdapter {
        VaultDataModelEditorAdapter(dataModel: dataModel, keyDeriverFactory: keyDeriverFactory)
    }

    private func anyOTPCodeDetailEdits() -> OTPCodeDetailEdits {
        .init(
            codeType: .totp,
            relativeOrder: .min,
            totpPeriodLength: 30,
            hotpCounterValue: 0,
            secretBase32String: "",
            algorithm: .sha1,
            numberOfDigits: 6,
            issuerTitle: "iss",
            accountNameTitle: "acc",
            description: "desc",
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            newKillphrase: "",
            tags: [],
            lockState: .notLocked,
            color: nil,
            showInQuickType: true,
        )
    }

    private func loadDigesters(on dataModel: VaultDataModel) async {
        await dataModel.loadKillphraseDigester()
        await dataModel.loadSearchPassphraseDigester()
    }

    private func assertSearchPassphrase(
        _ update: VaultItem.SearchPassphraseUpdate,
        matches phrase: String,
        using dataModel: VaultDataModel,
    ) {
        guard case let .set(digest) = update else {
            Issue.record("Expected search passphrase to be set, got \(update)")
            return
        }
        #expect(dataModel.searchPassphraseDigester?.matches(
            query: phrase,
            salt: digest.salt,
            digest: digest.digest,
        ) == true)
    }

    private func assertKillphrase(
        _ update: VaultItem.KillphraseUpdate,
        matches phrase: String,
        using dataModel: VaultDataModel,
    ) {
        guard case let .set(digest) = update else {
            Issue.record("Expected killphrase to be set, got \(update)")
            return
        }
        #expect(dataModel.killphraseDigester?.matches(
            query: phrase,
            salt: digest.salt,
            digest: digest.digest,
        ) == true)
    }
}
