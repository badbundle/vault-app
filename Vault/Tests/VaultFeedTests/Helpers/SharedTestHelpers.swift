import Foundation
import FoundationExtensions
import PDFKit
import VaultBackup
import VaultCore
import VaultFeed
import VaultKeygen

func uniqueCode() -> OTPAuthCode {
    let randomData = Data.random(count: 50)
    return OTPAuthCode(
        type: .totp(),
        data: .init(
            secret: .init(data: randomData, format: .base32),
            accountName: "Some Account",
        ),
    )
}

@MainActor
func anyVaultDataModel(
    vaultStore: some VaultStore = VaultStoreStub(),
    vaultTagStore: some VaultTagStore = VaultTagStoreStub(),
    vaultImporter: some VaultStoreImporter = VaultStoreImporterMock(),
    vaultDeleter: some VaultStoreDeleter = VaultStoreDeleterMock(),
    vaultKillphraseDeleter: some VaultStoreKillphraseDeleter = VaultStoreKillphraseDeleterMock(),
    vaultOtpAutofillStore: some VaultOTPAutofillStore = VaultOTPAutofillStoreMock(),
    backupPasswordStore: some BackupPasswordStore = BackupPasswordStoreMock(),
    killphraseKeyStore: (any KillphraseKeyStore<KeyData<32>>)? = nil,
    killphraseRehashService: KillphraseRehashService? = nil,
    searchPassphraseKeyStore: (any SearchPassphraseKeyStore<KeyData<32>>)? = nil,
    searchPassphraseRehashService: SearchPassphraseRehashService? = nil,
    backupEventLogger: some BackupEventLogger = BackupEventLoggerMock(),
) -> VaultDataModel {
    VaultDataModel(
        vaultStore: vaultStore,
        vaultTagStore: vaultTagStore,
        vaultImporter: vaultImporter,
        vaultDeleter: vaultDeleter,
        vaultKillphraseDeleter: vaultKillphraseDeleter,
        vaultOtpAutofillStore: vaultOtpAutofillStore,
        backupPasswordStore: backupPasswordStore,
        killphraseKeyStore: killphraseKeyStore ?? StubKillphraseKeyStore(),
        killphraseRehashService: killphraseRehashService,
        searchPassphraseKeyStore: searchPassphraseKeyStore ?? StubSearchPassphraseKeyStore(),
        searchPassphraseRehashService: searchPassphraseRehashService,
        backupEventLogger: backupEventLogger,
    )
}

/// Default no-op key store for VaultDataModel tests that don't exercise
/// the killphrase digest path. Returns a fixed all-zero key so
/// `loadOrCreate` never fatal-errors when called from `setup()`.
struct StubKillphraseKeyStore: KillphraseKeyStore {
    func loadOrCreate() async throws -> KeyData<32> {
        .zero()
    }
}

/// Default no-op key store for VaultDataModel tests that don't exercise
/// the search-passphrase digest path. Returns a fixed all-zero key.
struct StubSearchPassphraseKeyStore: SearchPassphraseKeyStore {
    func loadOrCreate() async throws -> KeyData<32> {
        .zero()
    }
}

func anyPDFData() throws -> Data {
    let path = randomTmpPath()
    let pdf = PDFDocument()
    // The document needs at least one page. A page-less PDF round-trips on iOS 26 but is rejected by
    // `PDFDocument(data:)` on iOS 27, and real export documents always carry pages regardless.
    pdf.insert(PDFPage(), at: 0)
    pdf.write(to: path)
    return try Data(contentsOf: path)
}

func anyHOTPCode() -> HOTPAuthCode {
    let codeData = OTPAuthCodeData(secret: .empty(), accountName: "Test")
    return .init(data: codeData)
}

func anyTOTPCode(period: UInt64 = 30) -> TOTPAuthCode {
    let codeData = OTPAuthCodeData(secret: .empty(), accountName: "Test")
    return .init(period: period, data: codeData)
}

func anyVaultApplicationPayload() -> VaultApplicationPayload {
    .init(userDescription: "", items: [], tags: [])
}

func randomTmpPath() -> URL {
    FileManager().temporaryDirectory.appending(path: UUID().uuidString)
}

func anyEncryptedVault(
    data: Data = .random(count: 50),
    salt: Data = .random(count: 32),
) -> EncryptedVault {
    EncryptedVault(
        version: "1.0.0",
        data: data,
        authentication: Data(),
        encryptionIV: Data(),
        keygenSalt: salt,
        keygenSignature: VaultKeyDeriver.Signature.testing.rawValue,
    )
}

func anyBackupPassword() -> DerivedEncryptionKey {
    .init(key: .random(), salt: .random(count: 32), keyDervier: .testing)
}

func testUserDefaults() throws -> UserDefaults {
    struct NoDefaults: Error {}
    let id = UUID()
    let defaults = UserDefaults(suiteName: id.uuidString)
    guard let defaults else { throw NoDefaults() }
    defaults.removePersistentDomain(forName: id.uuidString)
    return defaults
}

// MARK: - VaultItem

func anySecureNote(
    title: String = "",
    contents: String = "",
    format: TextFormat = .markdown,
) -> SecureNote {
    SecureNote(title: title, contents: contents, format: format)
}

/// The first BIP39 test vector: a valid 12 word English phrase.
let validBIP39Words = Array(repeating: "abandon", count: 11) + ["about"]

func anyRecoveryPhrase(
    title: String = "",
    words: [String] = validBIP39Words,
    standard: RecoveryPhraseStandard = .bip39,
    passphrase: String = "",
    contents: String = "",
) -> RecoveryPhrase {
    RecoveryPhrase(title: title, words: words, standard: standard, passphrase: passphrase, contents: contents)
}

/// Recovery phrases covering every standard, word count extremes and the scripts of the wordlists, for checking that
/// the words survive encoding exactly: same words, same order, same Unicode scalars.
let recoveryPhraseFixtures: [RecoveryPhrase] = [
    RecoveryPhrase(
        title: "English BIP39",
        words: Array(repeating: "abandon", count: 23) + ["art"],
        standard: .bip39,
        passphrase: "",
        contents: "",
    ),
    RecoveryPhrase(
        title: "Japanese BIP39",
        // Decomposed kana (as in the wordlist file), which must not be recomposed.
        words: [
            "あいこくしん",
            "あいさつ",
            "あいた\u{3099}",
            "あおそら",
            "あかちゃん",
            "あきる",
            "あけか\u{3099}た",
            "あける",
            "あこか\u{3099}れる",
            "あさい",
            "あさひ",
            "あしあと",
        ],
        standard: .bip39,
        passphrase: "パスフレーズ",
        contents: "日本語のメモ",
    ),
    RecoveryPhrase(
        title: "Chinese BIP39",
        words: ["的", "一", "是", "在", "不", "了", "有", "和", "人", "这", "中", "大"],
        standard: .bip39,
        passphrase: "",
        contents: "",
    ),
    RecoveryPhrase(
        title: "Spanish BIP39",
        // Both precomposed and decomposed accents.
        words: [
            "árbol",
            "a\u{301}baco",
            "niño",
            "nin\u{303}o",
            "peatón",
            "vehículo",
            "almíbar",
            "tibio",
            "superar",
            "vencer",
            "hacha",
            "odisea",
        ],
        standard: .bip39,
        passphrase: "contraseña",
        contents: "",
    ),
    RecoveryPhrase(
        title: "SLIP-39 share",
        words: ("theory painting academic academic armed sweater year military elder discuss acne wildlife boring "
            + "employer fused large satoshi bundle carbon diagnose anatomy hamster leaves tracks paces beyond phantom "
            + "capital marvel lips brave detect luck").split(separator: " ").map(String.init),
        standard: .slip39,
        passphrase: "",
        contents: "Share 1 of 3, 2 needed",
    ),
    RecoveryPhrase(
        title: "Electrum",
        words: "wild father tree among universe such mobile favorite target dynamic credit identify"
            .split(separator: " ").map(String.init),
        standard: .electrum,
        passphrase: "Did you ever hear the tragedy of Darth Plagueis the Wise?",
        contents: "",
    ),
    RecoveryPhrase(
        title: "Monero",
        words: ("velvet lymph giddy number token physics poetry unquoted nibs useful sabotage limits benches "
            + "lifestyle eden nitrogen anvil fewest avoid batch vials washing fences goat unquoted")
            .split(separator: " ").map(String.init),
        standard: .monero,
        passphrase: "",
        contents: "",
    ),
    RecoveryPhrase(
        title: "Other, 48 words",
        // Anything goes: mixed case, punctuation, emoji, repeats, and words that aren't in any list.
        words: (1 ... 48).map { index in index.isMultiple(of: 2) ? "Word-\(index)" : "🔑\(index)\"quoted\"" },
        standard: .other,
        // Whitespace is significant in a passphrase.
        passphrase: "  leading and trailing  \n",
        contents: "Line one\nLine two, with \"quotes\" and a backslash \\ and emoji 🪙",
    ),
    RecoveryPhrase(
        title: "",
        words: ["single"],
        standard: .other,
        passphrase: "",
        contents: "",
    ),
]

func anyEncryptedItem(title: String = "Hello") -> EncryptedItem {
    EncryptedItem(
        version: "1.0.0",
        title: title,
        data: Data.random(count: 10),
        authentication: Data.random(count: 10),
        encryptionIV: Data.random(count: 10),
        keygenSalt: Data.random(count: 10),
        keygenSignature: VaultKeyDeriver.Signature.testing.rawValue,
    )
}

func anyOTPAuthCode(
    type: OTPAuthType = .totp(),
    algorithm: OTPAuthAlgorithm = .default,
    digits: OTPAuthDigits = .default,
    accountName: String = "",
    issuerName: String = "",
) -> OTPAuthCode {
    let randomData = Data.random(count: 50)
    return OTPAuthCode(
        type: type,
        data: .init(
            secret: .init(data: randomData, format: .base32),
            algorithm: algorithm,
            digits: digits,
            accountName: accountName,
            issuer: issuerName,
        ),
    )
}

/// A unique vault item.
/// The default payload is any OTPAuthCode.
func uniqueVaultItem(
    id: Identifier<VaultItem> = .new(),
    item: VaultItem.Payload = .otpCode(anyOTPAuthCode()),
    relativeOrder: UInt64 = .min,
    updatedDate: Date = Date(),
    userDescription: String = "",
    visibility: VaultItemVisibility = .always,
    tags: Set<Identifier<VaultItemTag>> = [],
    searchableLevel: VaultItemSearchableLevel = .full,
    killphrase: String? = nil,
    lockState: VaultItemLockState = .notLocked,
) -> VaultItem {
    VaultItem(
        metadata: anyVaultItemMetadata(
            id: id,
            relativeOrder: relativeOrder,
            updatedDate: updatedDate,
            userDescription: userDescription,
            visibility: visibility,
            tags: tags,
            searchableLevel: searchableLevel,
            killphrase: killphrase.flatMap { phrase in
                phrase.isEmpty ? nil : testDigester.makeDigest(phrase: phrase)
            },
            lockState: lockState,
        ),
        item: item,
    )
}

/// A deterministic killphrase digester used to build test fixtures from
/// plaintext phrases. The key is zeroed so test assertions remain stable.
let testDigester: KillphraseDigester = {
    // swiftlint:disable:next force_try
    let key = try! KeyData<32>(data: Data(repeating: 0, count: 32))
    return KillphraseDigester(key: key)
}()

/// A unique vault item with custom metadata.
/// The default payload is any OTPAuthCode.
func uniqueVaultItem(
    metadata: VaultItem.Metadata,
    item: VaultItem.Payload = .otpCode(anyOTPAuthCode()),
) -> VaultItem {
    VaultItem(
        metadata: metadata,
        item: item,
    )
}

func anyVaultItemMetadata(
    id: Identifier<VaultItem> = .new(),
    relativeOrder: UInt64 = .min,
    updatedDate: Date = Date(),
    userDescription: String = "",
    visibility: VaultItemVisibility = .always,
    tags: Set<Identifier<VaultItemTag>> = [],
    searchableLevel: VaultItemSearchableLevel = .full,
    searchPassphrase: SearchPassphraseDigest? = nil,
    killphrase: KillphraseDigest? = nil,
    lockState: VaultItemLockState = .notLocked,
    color: VaultItemColor? = nil,
    showInQuickType: Bool = true,
    previewMode: NotePreviewMode = .titleAndFirstLine,
) -> VaultItem.Metadata {
    .init(
        id: id,
        created: Date(),
        updated: updatedDate,
        relativeOrder: relativeOrder,
        userDescription: userDescription,
        tags: tags,
        visibility: visibility,
        searchableLevel: searchableLevel,
        searchPassphrase: searchPassphrase,
        killphrase: killphrase,
        lockState: lockState,
        color: color,
        showInQuickType: showInQuickType,
        previewMode: previewMode,
    )
}

extension SecureNote {
    func wrapInAnyVaultItem(
        userDescription: String = "",
        visibility: VaultItemVisibility = .always,
        tags: Set<Identifier<VaultItemTag>> = [],
        searchableLevel: VaultItemSearchableLevel = .full,
        searchPassphrase: SearchPassphraseDigest? = nil,
        killphrase: KillphraseDigest? = nil,
        lockState: VaultItemLockState = .notLocked,
        showInQuickType: Bool = true,
        previewMode: NotePreviewMode = .titleAndFirstLine,
    ) -> VaultItem {
        VaultItem(
            metadata: anyVaultItemMetadata(
                userDescription: userDescription,
                visibility: visibility,
                tags: tags,
                searchableLevel: searchableLevel,
                searchPassphrase: searchPassphrase,
                killphrase: killphrase,
                lockState: lockState,
                showInQuickType: showInQuickType,
                previewMode: previewMode,
            ),
            item: .secureNote(self),
        )
    }
}

extension EncryptedItem {
    func wrapInAnyVaultItem(
        userDescription: String = "",
        visibility: VaultItemVisibility = .always,
        tags: Set<Identifier<VaultItemTag>> = [],
        searchableLevel: VaultItemSearchableLevel = .full,
        searchPassphrase: SearchPassphraseDigest? = nil,
        killphrase: KillphraseDigest? = nil,
        lockState: VaultItemLockState = .notLocked,
        showInQuickType: Bool = true,
        previewMode: NotePreviewMode = .titleAndFirstLine,
    ) -> VaultItem {
        VaultItem(
            metadata: anyVaultItemMetadata(
                userDescription: userDescription,
                visibility: visibility,
                tags: tags,
                searchableLevel: searchableLevel,
                searchPassphrase: searchPassphrase,
                killphrase: killphrase,
                lockState: lockState,
                showInQuickType: showInQuickType,
                previewMode: previewMode,
            ),
            item: .encryptedItem(self),
        )
    }
}

extension OTPAuthCode {
    func wrapInAnyVaultItem(
        userDescription: String = "",
        visibility: VaultItemVisibility = .always,
        tags: Set<Identifier<VaultItemTag>> = [],
        searchableLevel: VaultItemSearchableLevel = .full,
        searchPassphrase: SearchPassphraseDigest? = nil,
        killphrase: KillphraseDigest? = nil,
        lockState: VaultItemLockState = .notLocked,
        color: VaultItemColor? = nil,
        showInQuickType: Bool = true,
    ) -> VaultItem {
        VaultItem(
            metadata: anyVaultItemMetadata(
                userDescription: userDescription,
                visibility: visibility,
                tags: tags,
                searchableLevel: searchableLevel,
                searchPassphrase: searchPassphrase,
                killphrase: killphrase,
                lockState: lockState,
                color: color,
                showInQuickType: showInQuickType,
            ),
            item: .otpCode(self),
        )
    }
}

// MARK: - VaultItemTag

func anyVaultItemTag(
    id: UUID = UUID(),
    name: String = "name",
    color: VaultItemColor = .tagDefault,
    iconName: String = VaultItemTag.defaultIconName,
) -> VaultItemTag {
    VaultItemTag(id: .init(id: id), name: name, color: color, iconName: iconName)
}

// MARK: - Constants

func hotpRfcSecretData() -> Data {
    Data([
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
        0x37,
        0x38,
        0x39,
        0x30,
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
        0x37,
        0x38,
        0x39,
        0x30,
    ])
}

// MARK: - Misc

struct TestError: Error {}

extension UserDefaults {
    var keys: Set<String> {
        dictionaryRepresentation().keys.reducedToSet()
    }
}

struct VaultItemEncryptedContainerMock: VaultItemEncryptedContainer {
    var itemIdentifier: String = "test"
    var id: UUID
    var exampleKey: String = "exampleValue"
    var title: String = "hello"
}

struct VaultItemEncryptableMock: Equatable, VaultItemEncryptable {
    typealias EncryptedContainer = VaultItemEncryptedContainerMock
    var id: UUID
    var itemIdentifier: String
    let exampleKey: String
    let title: String

    init(
        itemIdentifier: String = "test",
        id: UUID = UUID(),
        exampleKey: String = "exampleValue",
        title: String = "hello",
    ) {
        self.itemIdentifier = itemIdentifier
        self.id = id
        self.exampleKey = exampleKey
        self.title = title
    }

    init(encryptedContainer: VaultItemEncryptedContainerMock) {
        self = .init(
            itemIdentifier: encryptedContainer.itemIdentifier,
            id: encryptedContainer.id,
            exampleKey: encryptedContainer.exampleKey,
            title: encryptedContainer.title,
        )
    }

    func makeEncryptedContainer() throws -> VaultItemEncryptedContainerMock {
        .init(
            itemIdentifier: itemIdentifier,
            id: id,
            exampleKey: exampleKey,
            title: title,
        )
    }
}

/// A generated PDF of blank pages.
func anyGeneratedPDF(
    pageCount: Int = 1,
    createdDate: Date = Date(timeIntervalSince1970: 100),
) -> BackupCreatePDFViewModel.GeneratedPDF {
    let document = PDFDocument()
    for index in 0 ..< pageCount {
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 595, height: 842), for: .mediaBox)
        document.insert(page, at: index)
    }
    return BackupCreatePDFViewModel.GeneratedPDF(
        document: document,
        size: .a4,
        dataHash: .init(value: Data(repeating: 0xAB, count: 32)),
        createdDate: createdDate,
    )
}
