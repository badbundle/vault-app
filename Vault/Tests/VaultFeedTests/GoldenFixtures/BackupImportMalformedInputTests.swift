import Foundation
import FoundationExtensions
import PDFKit
import Testing
import VaultBackup
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// Malformed input at every step of a restore ends in an error: the PDF, the QR codes, the backup's JSON, its
/// decompression and the payload's JSON. Each step also gets a small seeded fuzz test, with a time limit, of
/// changes to a real backup from the corpus.
struct BackupImportMalformedInputTests {}

// MARK: - The PDF

extension BackupImportMalformedInputTests {
    @MainActor
    @Test(arguments: [0, 0.01, 0.25, 0.5, 0.75, 0.99])
    func pdf_truncated_endsInAnError(fraction: Double) async throws {
        let data = try BackupCorpusEntry.pdfWithRandomPadding.data()

        let state = try await importState(ofPDF: data.prefix(Int(Double(data.count) * fraction)))

        #expect(state.isError)
    }

    @Test
    func pdf_thatIsNotAPDF_endsInAnError() throws {
        var generator = SeededRandomNumberGenerator(seed: 87)

        for data in [Data(), Data("%PDF-1.7".utf8), bytes(count: 4096, using: &generator)] {
            #expect(throws: (any Error).self) { try detach(fromPDF: data) }
        }
    }

    @Test(arguments: [
        nil,
        "",
        VaultIdentifiers.Backup.encryptedVaultData,
        VaultIdentifiers.Backup.encryptedVaultData + ":",
        VaultIdentifiers.Backup.encryptedVaultData + ":not base64!",
        VaultIdentifiers.Backup.encryptedVaultData + ":" + Data("{}".utf8).base64EncodedString(),
        VaultIdentifiers.Backup.encryptedVaultData + ":" + Data("[1, 2, 3]".utf8).base64EncodedString(),
    ] as [String?])
    func pdf_whoseBackupIsMissingOrMalformed_endsInAnError(contents: String?) throws {
        let data = try pdf(annotatedWith: contents)

        #expect(throws: (any Error).self) { try detach(fromPDF: data) }
    }

    @Test
    func pdf_whoseBackupIsFarLargerThanABackup_endsInAnError() throws {
        let contents = VaultIdentifiers.Backup.encryptedVaultData + ":"
            + Data(repeating: 0x7B, count: 4 << 20).base64EncodedString()
        let data = try pdf(annotatedWith: contents)

        #expect(throws: (any Error).self) { try detach(fromPDF: data) }
    }

    @Test
    func pdf_whoseBackupIsTruncated_endsInAnError() throws {
        let json = try encryptedVaultJSON()

        for length in [1, json.count / 2, json.count - 1] {
            let contents = VaultIdentifiers.Backup.encryptedVaultData + ":" + json.prefix(length).base64EncodedString()
            let data = try pdf(annotatedWith: contents)
            #expect(throws: (any Error).self, "\(length)") { try detach(fromPDF: data) }
        }
    }

    /// The PDF's bytes changed, then read as importing reads them.
    @Test(.timeLimit(.minutes(1)))
    func pdf_fuzzed_neverCrashes() async throws {
        let data = try BackupCorpusEntry.pdfWithRandomPadding.data()
        var generator = SeededRandomNumberGenerator(seed: 1)

        try await fuzz(data, iterations: 40, using: &generator) { mutated in
            _ = try? detach(fromPDF: mutated)
        }
    }
}

// MARK: - The QR codes

extension BackupImportMalformedInputTests {
    @Test
    func code_thatIsNotACode_isReportedAsInvalid() throws {
        let code = try firstTransferCode()
        let codes = [
            "",
            "hello",
            "{}",
            #"{"G":{"I":0,"ID":1,"N":1}}"#,
            #"{"D":"not base64!","G":{"I":0,"ID":1,"N":1}}"#,
            #"{"D":"","G":{"I":"0","ID":1,"N":1}}"#,
            String(code.prefix(code.count / 2)),
            String(repeating: "[", count: 10000),
            #"{"D":""# + String(repeating: "A", count: 4 << 20) + #"","G":{"I":0,"ID":1,"N":1}}"# + "!",
        ]

        for code in codes {
            let result = BackupImportScanningHandler().decode(data: code)
            #expect(result == .continueScanning(.invalidCode), "\(code.prefix(40))")
        }
    }

    /// Codes whose totals disagree complete early, and what they join into isn't a backup.
    @Test
    func codesWithTotalsThatDisagree_endInAnError() throws {
        let handler = BackupImportScanningHandler()

        let first = handler.decode(data: shardText(group: 7, number: 0, total: 3))
        let second = handler.decode(data: shardText(group: 7, number: 1, total: 1))

        #expect(first == .continueScanning(.success))
        #expect(second == .endScanning(.unrecoverableError))
    }

    @Test
    func codesOfOneBackup_withAPositionPastTheirTotal_neverComplete() throws {
        let handler = BackupImportScanningHandler()

        for number in [5, 6, -1] {
            #expect(handler.decode(data: shardText(group: 7, number: number, total: 2)) == .continueScanning(.success))
        }

        #expect(handler.shardState?.remainingShardIndexes == [0, 1])
    }

    /// Random codes, of a few groups, at any position, with totals up to 64, and some of them not codes at all.
    @Test(.timeLimit(.minutes(1)))
    func codes_fuzzed_neverCrash() throws {
        var generator = SeededRandomNumberGenerator(seed: 2)
        let real = try firstTransferCode()
        let deadline = ContinuousClock.now + .seconds(1)

        for _ in 0 ..< 200 where ContinuousClock.now < deadline {
            let handler = BackupImportScanningHandler()
            for _ in 0 ..< Int.random(in: 1 ... 20, using: &generator) {
                let text = switch Int.random(in: 0 ..< 10, using: &generator) {
                case 0: text(of: mutated(Data(real.utf8), using: &generator))
                case 1: text(of: bytes(count: .random(in: 0 ... 64, using: &generator), using: &generator))
                default: shardText(
                        group: .random(in: 1 ... 3, using: &generator),
                        number: .random(in: -2 ... 66, using: &generator),
                        total: .random(in: 0 ... 64, using: &generator),
                        data: bytes(count: .random(in: 0 ... 600, using: &generator), using: &generator),
                    )
                }
                if case .endScanning = handler.decode(data: text) {
                    break
                }
            }
        }
    }
}

// MARK: - The backup's JSON

extension BackupImportMalformedInputTests {
    @Test(arguments: [
        "",
        "{}",
        "[]",
        #"{"ENCRYPTION_VERSION":"1.0.0"}"#,
        #"{"ENCRYPTION_VERSION":1,"ENCRYPTION_DATA":"","ENCRYPTION_AUTH_TAG":"","ENCRYPTION_IV":"","KEYGEN_SALT":"","KEYGEN_SIGNATURE":""}"#,
        #"{"ENCRYPTION_VERSION":"1.0.0","ENCRYPTION_DATA":"!","ENCRYPTION_AUTH_TAG":"","ENCRYPTION_IV":"","KEYGEN_SALT":"","KEYGEN_SIGNATURE":""}"#,
    ])
    func encryptedVaultJSON_malformed_endsInAnError(json: String) {
        #expect(throws: (any Error).self) {
            try EncryptedVaultCoder().decode(vaultData: Data(json.utf8))
        }
    }

    @Test
    func encryptedVaultJSON_truncated_endsInAnError() throws {
        let json = try encryptedVaultJSON()

        for length in [0, 1, json.count / 3, json.count - 2] {
            #expect(throws: (any Error).self, "\(length)") {
                try EncryptedVaultCoder().decode(vaultData: json.prefix(length))
            }
        }
    }

    /// A backup that doesn't open, with the right password: a newer version, or a changed IV, tag or ciphertext.
    @Test
    func encryptedVault_changed_endsInAnError() throws {
        let vault = try encryptedVault()
        let key = try BackupCorpus.key(for: vault)
        var changes = [EncryptedVault]()
        changes.append(changing(vault) { $0.version = "2.0.0" })
        changes.append(changing(vault) { $0.encryptionIV = Data() })
        changes.append(changing(vault) { $0.encryptionIV = $0.encryptionIV.dropLast() })
        changes.append(changing(vault) { $0.authentication = Data($0.authentication.reversed()) })
        changes.append(changing(vault) { $0.data = $0.data.dropLast() })
        changes.append(changing(vault) { $0.data.append(0) })

        for (index, changed) in changes.enumerated() {
            #expect(throws: (any Error).self, "\(index)") {
                try EncryptedVaultDecoderImpl().decryptAndDecode(key: key, encryptedVault: changed)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func encryptedVaultJSON_fuzzed_neverCrashes() async throws {
        let json = try encryptedVaultJSON()
        let key = try BackupCorpus.key(for: encryptedVault())
        var generator = SeededRandomNumberGenerator(seed: 4)

        try await fuzz(json, iterations: 300, using: &generator) { mutated in
            guard let vault = try? EncryptedVaultCoder().decode(vaultData: mutated) else { return }
            _ = try? EncryptedVaultDecoderImpl().decryptAndDecode(key: key, encryptedVault: vault)
        }
    }
}

// MARK: - Decompression

extension BackupImportMalformedInputTests {
    /// Sealed with the right key, so it opens, but it isn't what the payload is compressed as.
    @Test
    func payload_thatDoesNotDecompress_endsInAnError() throws {
        let compressed = try compressedPayload()
        var generator = SeededRandomNumberGenerator(seed: 5)
        let payloads = [
            Data(),
            Data("{}".utf8),
            bytes(count: 4096, using: &generator),
            compressed.prefix(compressed.count / 2),
            compressed.dropLast(),
            compressed + compressed,
        ]

        for (index, payload) in payloads.enumerated() {
            #expect(throws: EncryptedVaultDecoderError.decoding, "\(index)") {
                try EncryptedVaultDecoderImpl().decryptAndDecode(key: sealingKey, encryptedVault: sealed(payload))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func compressedPayload_fuzzed_neverCrashes() async throws {
        let compressed = try compressedPayload()
        var generator = SeededRandomNumberGenerator(seed: 6)

        try await fuzz(compressed, iterations: 300, using: &generator) { mutated in
            _ = try? EncryptedVaultDecoderImpl().decryptAndDecode(key: sealingKey, encryptedVault: sealed(mutated))
        }
    }
}

// MARK: - The payload's JSON

extension BackupImportMalformedInputTests {
    @Test(arguments: [
        "",
        "{}",
        "[]",
        "null",
        #"{"version":"1.0.0"}"#,
        #"{"version":"1.0.0","created":0,"user_description":"","tags":[],"items":{},"obfuscation_padding":""}"#,
        #"{"version":"1.0.0","created":"yesterday","user_description":"","tags":[],"items":[],"obfuscation_padding":""}"#,
        #"{"version":"x","created":0,"user_description":"","tags":[],"items":[],"obfuscation_padding":""}"#,
    ])
    func payloadJSON_malformed_endsInAnError(json: String) throws {
        let compressed = try (Data(json.utf8) as NSData).compressed(using: .lzma) as Data

        #expect(throws: EncryptedVaultDecoderError.decoding) {
            try EncryptedVaultDecoderImpl().decryptAndDecode(key: sealingKey, encryptedVault: sealed(compressed))
        }
    }

    /// The corpus backup's payload with one of its items changed so it can't be read: an unknown value, a missing
    /// field, a value of the wrong type, or a number out of range.
    @Test(arguments: [
        (#""visibility" : "ALWAYS""#, #""visibility" : "SOMETIMES""#),
        (#""searchable_level" : "FULL""#, #""searchable_level" : 7"#),
        (#""lock_state" : "NOT_LOCKED""#, #""lock_state" : null"#),
        (#""digits" : 6"#, #""digits" : 70000"#),
        (#""digits" : 6"#, #""digits" : -6"#),
        (#""counter" : 42"#, #""counter" : 1e400"#),
        (#""relative_order" : 0"#, #""relative_order" : -1"#),
        (#""auth_type" : "totp""#, #""auth_type" : "sometimes""#),
        (#""algorithm" : "SHA1""#, #""algorithm" : "MD5""#),
        (#""id" : "ED314A19-B48C-430A-B280-6540D860542C""#, #""id" : "not a uuid""#),
    ])
    func payloadJSON_withAnItemThatCanNotBeRead_endsInAnError(change: (String, String)) throws {
        let json = try #require(String(bytes: payloadJSON(), encoding: .utf8))
        #expect(json.contains(change.0))
        let changed = json.replacingOccurrences(of: change.0, with: change.1)
        let compressed = try (Data(changed.utf8) as NSData).compressed(using: .lzma) as Data

        #expect(throws: (any Error).self) {
            try EncryptedVaultDecoderImpl().decryptAndDecode(key: sealingKey, encryptedVault: sealed(compressed))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func payloadJSON_fuzzed_neverCrashes() async throws {
        let json = try payloadJSON()
        var generator = SeededRandomNumberGenerator(seed: 7)

        try await fuzz(json, iterations: 300, using: &generator) { mutated in
            let compressed = try (mutated as NSData).compressed(using: .lzma) as Data
            _ = try? EncryptedVaultDecoderImpl().decryptAndDecode(key: sealingKey, encryptedVault: sealed(compressed))
        }
    }
}

// MARK: - Helpers

extension BackupImportMalformedInputTests {
    /// What importing the PDF comes to, before any password is asked for.
    @MainActor
    private func importState(ofPDF data: Data) async throws -> BackupImportFlowViewModel.PayloadState {
        let flow = try RestoreHarness.plain().makeImportFlow(context: .merge)
        await flow.handleImport(fromPDF: .success(data))
        return flow.payloadState
    }

    struct NotAPDF: Error {}

    /// Reads the backup out of the PDF as importing one does (`BackupImportFlowViewModel.handleImport(fromPDF:)`).
    private func detach(fromPDF data: Data) throws -> EncryptedVault {
        guard let document = PDFDocument(data: data) else { throw NotAPDF() }
        return try VaultBackupPDFDetatcherImpl().detachEncryptedVault(fromPDF: document)
    }

    /// A one-page PDF with an annotation holding `contents`, where a backup PDF holds its backup, or no annotation.
    private func pdf(annotatedWith contents: String?) throws -> Data {
        let document = PDFDocument()
        let page = PDFPage()
        if let contents {
            let annotation = PDFAnnotation(
                bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
                forType: .circle,
                withProperties: nil,
            )
            annotation.contents = contents
            page.addAnnotation(annotation)
        }
        document.insert(page, at: 0)
        return try #require(document.dataRepresentation())
    }

    /// The randomly padded corpus backup, which is small and quick to open.
    private func encryptedVault() throws -> EncryptedVault {
        let document = try #require(PDFDocument(data: BackupCorpusEntry.pdfWithRandomPadding.data()))
        return try VaultBackupPDFDetatcherImpl().detachEncryptedVault(fromPDF: document)
    }

    private func encryptedVaultJSON() throws -> Data {
        try EncryptedVaultCoder().encode(vault: encryptedVault())
    }

    /// The corpus backup's payload, compressed, as it's sealed.
    private func compressedPayload() throws -> Data {
        let vault = try encryptedVault()
        let key = try BackupCorpus.key(for: vault)
        return try AESGCMDecryptor(key: key.data).decrypt(
            message: .init(ciphertext: vault.data, authenticationTag: vault.authentication),
            iv: vault.encryptionIV,
        )
    }

    /// The corpus backup's payload JSON.
    private func payloadJSON() throws -> Data {
        try (compressedPayload() as NSData).decompressed(using: .lzma) as Data
    }

    private var sealingKey: KeyData<32> {
        .repeating(byte: 0x5A)
    }

    /// `payload` sealed as a backup's payload is, with `sealingKey`, so it opens and what's inside is read.
    private func sealed(_ payload: Data) throws -> EncryptedVault {
        let iv = Data(repeating: 0x01, count: 32)
        let message = try AESGCMEncryptor(key: sealingKey.data).encrypt(plaintext: payload, iv: iv)
        return EncryptedVault(
            version: "1.0.0",
            data: message.ciphertext,
            authentication: message.authenticationTag,
            encryptionIV: iv,
            keygenSalt: Data(),
            keygenSignature: VaultKeyDeriver.Signature.backupFastV1.rawValue,
        )
    }

    private func changing(_ vault: EncryptedVault, _ change: (inout EncryptedVault) -> Void) -> EncryptedVault {
        var vault = vault
        change(&vault)
        return vault
    }

    private func firstTransferCode() throws -> String {
        try #require(JSONDecoder().decode([String].self, from: BackupCorpusEntry.transferQRCodes.data()).first)
    }

    /// A code's text, as a transfer writes it.
    private func shardText(group: UInt16, number: Int, total: Int, data: Data = Data([1, 2, 3])) -> String {
        #"{"D":"\#(data.base64EncodedString())","G":{"I":\#(number),"ID":\#(group),"N":\#(total)}}"#
    }

    /// Changes `data` `iterations` times, one to a few edits each (a byte changed, removed, repeated or inserted, or
    /// the data cut short), and hands each to `body`, until the iterations or a second run out.
    private func fuzz(
        _ data: Data,
        iterations: Int,
        using generator: inout SeededRandomNumberGenerator,
        _ body: (Data) async throws -> Void,
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        for _ in 0 ..< iterations where ContinuousClock.now < deadline {
            try await body(mutated(data, using: &generator))
        }
    }

    private func mutated(_ data: Data, using generator: inout SeededRandomNumberGenerator) -> Data {
        var bytes = [UInt8](data)
        for _ in 0 ..< Int.random(in: 1 ... 4, using: &generator) where !bytes.isEmpty {
            let index = Int.random(in: 0 ..< bytes.count, using: &generator)
            switch Int.random(in: 0 ..< 5, using: &generator) {
            case 0: bytes[index] = .random(in: 0 ... 255, using: &generator)
            case 1: bytes.remove(at: index)
            case 2: bytes.insert(bytes[index], at: index)
            case 3: bytes.insert(.random(in: 0 ... 255, using: &generator), at: index)
            default: bytes.removeLast(bytes.count - index)
            }
        }
        return Data(bytes)
    }

    /// Any bytes as text, a character for each, as a scanner could read them.
    private func text(of data: Data) -> String {
        String(bytes: data, encoding: .isoLatin1) ?? ""
    }

    private func bytes(count: Int, using generator: inout SeededRandomNumberGenerator) -> Data {
        Data((0 ..< count).map { _ in UInt8.random(in: 0 ... 255, using: &generator) })
    }
}

extension BackupCorpus {
    /// The key a backup's password derives, as restoring it derives it.
    static func key(for vault: EncryptedVault) throws -> KeyData<32> {
        let signature = try VaultKeyDeriver.Signature(tryFromString: vault.keygenSignature)
        return try VaultKeyDeriver.lookup(signature: signature)
            .recreateEncryptionKey(password: password, salt: vault.keygenSalt)
            .key
    }
}
