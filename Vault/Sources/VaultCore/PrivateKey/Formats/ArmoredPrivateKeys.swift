import Foundation

/// Reads what an armored private key says about itself: its kind, and its algorithm where that's cheap to find. Nothing
/// is decrypted, and nothing is derived.
enum ArmoredPrivateKeys {
    static func validate(_ text: String) -> PrivateKeyValidation.Status {
        switch ArmoredBlock.parse(text) {
        case .none:
            return .unrecognized
        case let .unreadable(label):
            guard let kind = privateKeyKind(label: label) else { return publicKeyStatus(label: label) }
            return .malformed(kind, .unreadable)
        case let .block(block):
            switch block.label {
            case "OPENSSH PRIVATE KEY":
                return openSSH(block)
            case "PGP PRIVATE KEY BLOCK":
                return openPGP(block)
            case "RSA PRIVATE KEY":
                return pem(block, encoding: .pkcs1)
            case "EC PRIVATE KEY":
                return pem(block, encoding: .sec1)
            case "DSA PRIVATE KEY":
                return pem(block, encoding: .dsa)
            case "PRIVATE KEY":
                return pkcs8(block)
            case "ENCRYPTED PRIVATE KEY":
                return encryptedPKCS8(block)
            default:
                return publicKeyStatus(label: block.label)
            }
        }
    }

    private static func privateKeyKind(label: String) -> PrivateKeyKind? {
        switch label {
        case "OPENSSH PRIVATE KEY": .openSSH
        case "PGP PRIVATE KEY BLOCK": .openPGP
        case "RSA PRIVATE KEY", "EC PRIVATE KEY", "DSA PRIVATE KEY", "PRIVATE KEY", "ENCRYPTED PRIVATE KEY": .pem
        default: nil
        }
    }

    /// A public key block entered by mistake, or something that isn't a key at all, like a certificate.
    private static func publicKeyStatus(label: String) -> PrivateKeyValidation.Status {
        switch label {
        case "PGP PUBLIC KEY BLOCK": .publicKey(.openPGP)
        case "PUBLIC KEY", "RSA PUBLIC KEY", "EC PUBLIC KEY": .publicKey(.pem)
        default: .unrecognized
        }
    }

    // MARK: - OpenSSH

    /// `openssh-key-v1` (PROTOCOL.key): the magic, the cipher, KDF and its options, the number of keys, each public
    /// key, then the private keys, encrypted unless the cipher is "none". Unencrypted, the private section starts with
    /// two check numbers that must be the same.
    private static func openSSH(_ block: ArmoredBlock) -> PrivateKeyValidation.Status {
        let magic = Array("openssh-key-v1".utf8) + [0]
        guard block.data.starts(with: magic) else { return .malformed(.openSSH, .unreadable) }
        var reader = SSHWireReader(block.data.dropFirst(magic.count))
        guard
            let cipher = reader.readString(),
            reader.readString() != nil, // KDF name
            reader.readString() != nil, // KDF options
            let keyCount = reader.readUInt32(),
            (1 ... 64).contains(keyCount),
            let publicKey = reader.readString()
        else { return .malformed(.openSSH, .unreadable) }
        for _ in 1 ..< keyCount {
            guard reader.readString() != nil else { return .malformed(.openSSH, .unreadable) }
        }
        guard let privateSection = reader.readString() else { return .malformed(.openSSH, .unreadable) }

        let isEncrypted = String(bytes: cipher, encoding: .utf8) != "none"
        if !isEncrypted {
            var privateReader = SSHWireReader(privateSection)
            guard let first = privateReader.readUInt32(), let second = privateReader.readUInt32() else {
                return .malformed(.openSSH, .unreadable)
            }
            guard first == second else { return .malformed(.openSSH, .inconsistent) }
        }

        var publicKeyReader = SSHWireReader(publicKey)
        let keyType = publicKeyReader.readString().flatMap { String(bytes: $0, encoding: .utf8) }
        return .valid(.openSSH(algorithm: keyType.flatMap(sshAlgorithm), isPassphraseProtected: isEncrypted))
    }

    private static func sshAlgorithm(_ keyType: String) -> PrivateKeyAlgorithm? {
        switch keyType {
        case "ssh-ed25519": .ed25519
        case "ssh-rsa": .rsa
        case "ssh-dss": .dsa
        case "ecdsa-sha2-nistp256": .ecdsa(.p256)
        case "ecdsa-sha2-nistp384": .ecdsa(.p384)
        case "ecdsa-sha2-nistp521": .ecdsa(.p521)
        case "sk-ssh-ed25519@openssh.com": .ed25519SecurityKey
        case "sk-ecdsa-sha2-nistp256@openssh.com": .ecdsaSecurityKey
        default: nil
        }
    }

    // MARK: - OpenPGP

    /// The armor's CRC-24, if it has one, then the first packet, which must be a secret key (tag 5): its version,
    /// creation time and algorithm (RFC 9580, sections 4.2 and 5.5.3).
    private static func openPGP(_ block: ArmoredBlock) -> PrivateKeyValidation.Status {
        if let checksum = block.checksum, checksum != CRC24.checksum(block.data) {
            return .invalidChecksum(.openPGP)
        }
        guard let (tag, body) = firstOpenPGPPacket(in: block.data) else { return .malformed(.openPGP, .unreadable) }
        switch tag {
        case 5:
            return .valid(.openPGP(algorithm: openPGPAlgorithm(secretKeyBody: body)))
        case 6:
            return .publicKey(.openPGP)
        default:
            return .malformed(.openPGP, .unreadable)
        }
    }

    /// The tag and body of the first packet, in the old or the new packet format (RFC 9580, section 4.2).
    private static func firstOpenPGPPacket(in data: [UInt8]) -> (tag: UInt8, body: ArraySlice<UInt8>)? {
        guard let header = data.first, header & 0x80 != 0, data.count >= 2 else { return nil }
        let tag: UInt8
        let headerLength: Int
        let length: Int?
        if header & 0x40 != 0 {
            tag = header & 0x3F
            let first = Int(data[1])
            switch first {
            case 0 ..< 192:
                headerLength = 2
                length = first
            case 192 ..< 224:
                guard data.count >= 3 else { return nil }
                headerLength = 3
                length = ((first - 192) << 8) + Int(data[2]) + 192
            case 255:
                guard data.count >= 6 else { return nil }
                headerLength = 6
                length = data[2 ..< 6].reduce(0) { $0 << 8 | Int($1) }
            default:
                // A partial body length: the first part is enough to read the start of the key.
                headerLength = 2
                length = nil
            }
        } else {
            tag = (header >> 2) & 0x0F
            switch header & 0x03 {
            case 0:
                headerLength = 2
                length = Int(data[1])
            case 1:
                guard data.count >= 3 else { return nil }
                headerLength = 3
                length = Int(data[1]) << 8 | Int(data[2])
            case 2:
                guard data.count >= 5 else { return nil }
                headerLength = 5
                length = data[1 ..< 5].reduce(0) { $0 << 8 | Int($1) }
            default:
                headerLength = 1
                length = nil
            }
        }
        let body = data.dropFirst(headerLength)
        if let length {
            guard body.count >= length else { return nil }
            return (tag, body.prefix(length))
        }
        return (tag, body)
    }

    /// Version 4, 5 and 6 keys have their algorithm after a 4-byte creation time, and version 3 after a 2-byte
    /// validity period as well (RFC 9580, section 5.5.2). An elliptic curve key names its curve with an OID next.
    private static func openPGPAlgorithm(secretKeyBody body: ArraySlice<UInt8>) -> PrivateKeyAlgorithm? {
        guard let version = body.first else { return nil }
        let algorithmOffset = switch version {
        case 2, 3: 7
        case 4, 5, 6: 5
        default: -1
        }
        guard algorithmOffset > 0, body.count > algorithmOffset else { return nil }
        let algorithmIndex = body.startIndex + algorithmOffset
        let afterAlgorithm = body[(algorithmIndex + 1)...]
        let curve = openPGPCurveOID(afterAlgorithm)
        return switch body[algorithmIndex] {
        case 1, 2, 3: .rsa
        case 16: .elGamal
        case 17: .dsa
        case 18: .ecdh(curve.flatMap(ellipticCurve(oid:)))
        case 19: .ecdsa(curve.flatMap(ellipticCurve(oid:)))
        case 22: curve == OID.ed25519Legacy ? .ed25519 : .eddsa
        case 25: .x25519
        case 26: .x448
        case 27: .ed25519
        case 28: .ed448
        default: nil
        }
    }

    /// The OID that starts an elliptic curve key's public part, after a length byte (RFC 9580, section 5.5.5).
    private static func openPGPCurveOID(_ bytes: ArraySlice<UInt8>) -> [UInt8]? {
        guard let length = bytes.first, (1 ... 0xFE).contains(length), bytes.count > Int(length) else { return nil }
        return Array(bytes.dropFirst().prefix(Int(length)))
    }

    // MARK: - PEM

    /// PKCS #1, SEC 1 or OpenSSL's DSA, as `openssl` writes them: one SEQUENCE. A legacy encrypted key says so in its
    /// headers ("Proc-Type: 4,ENCRYPTED", RFC 1421), and its DER is encrypted, so it isn't read.
    private static func pem(_ block: ArmoredBlock, encoding: PEMKeyEncoding) -> PrivateKeyValidation.Status {
        let isEncrypted = block.headers.contains { $0.name == "Proc-Type" && $0.value.contains("ENCRYPTED") }
        let algorithm: PrivateKeyAlgorithm = switch encoding {
        case .pkcs1: .rsa
        case .dsa: .dsa
        case .sec1, .pkcs8: .ec(nil)
        }
        if isEncrypted {
            return .valid(.pem(encoding, algorithm: algorithm, isEncrypted: true))
        }
        var outer = DERReader(block.data)
        guard let sequence = outer.read(tag: DERReader.sequence), outer.isAtEnd else {
            return .malformed(.pem, .unreadable)
        }
        var reader = DERReader(sequence)
        guard reader.read(tag: DERReader.integer) != nil else { return .malformed(.pem, .unreadable) }
        guard encoding == .sec1 else {
            return .valid(.pem(encoding, algorithm: algorithm, isEncrypted: false))
        }
        // ECPrivateKey (RFC 5915): the version, the key, then the curve's OID in a [0].
        guard reader.read(tag: DERReader.octetString) != nil else { return .malformed(.pem, .unreadable) }
        var curve: EllipticCurve?
        if let parameters = reader.read(tag: 0xA0) {
            var parametersReader = DERReader(parameters)
            curve = parametersReader.read(tag: DERReader.objectIdentifier).flatMap { ellipticCurve(oid: Array($0)) }
        }
        return .valid(.pem(.sec1, algorithm: .ec(curve), isEncrypted: false))
    }

    /// PrivateKeyInfo (RFC 5208, and RFC 5958's OneAsymmetricKey): the version, then the algorithm's OID and its
    /// parameters, which for an elliptic curve key are its curve.
    private static func pkcs8(_ block: ArmoredBlock) -> PrivateKeyValidation.Status {
        var outer = DERReader(block.data)
        guard let sequence = outer.read(tag: DERReader.sequence), outer.isAtEnd else {
            return .malformed(.pem, .unreadable)
        }
        var reader = DERReader(sequence)
        guard
            reader.read(tag: DERReader.integer) != nil,
            let algorithmIdentifier = reader.read(tag: DERReader.sequence),
            reader.read(tag: DERReader.octetString) != nil
        else { return .malformed(.pem, .unreadable) }
        var algorithmReader = DERReader(algorithmIdentifier)
        guard let oid = algorithmReader.read(tag: DERReader.objectIdentifier).map(Array.init) else {
            return .malformed(.pem, .unreadable)
        }
        let algorithm: PrivateKeyAlgorithm? = switch oid {
        case OID.rsaEncryption: .rsa
        case OID.dsa: .dsa
        case OID.ecPublicKey:
            .ec(algorithmReader.read(tag: DERReader.objectIdentifier).flatMap { ellipticCurve(oid: Array($0)) })
        case OID.ed25519: .ed25519
        case OID.ed448: .ed448
        case OID.x25519: .x25519
        case OID.x448: .x448
        default: nil
        }
        return .valid(.pem(.pkcs8, algorithm: algorithm, isEncrypted: false))
    }

    /// EncryptedPrivateKeyInfo (RFC 5208, section 6): how it's encrypted, then the encrypted key. What's inside can't
    /// be read without its password.
    private static func encryptedPKCS8(_ block: ArmoredBlock) -> PrivateKeyValidation.Status {
        var outer = DERReader(block.data)
        guard let sequence = outer.read(tag: DERReader.sequence), outer.isAtEnd else {
            return .malformed(.pem, .unreadable)
        }
        var reader = DERReader(sequence)
        guard
            reader.read(tag: DERReader.sequence) != nil,
            reader.read(tag: DERReader.octetString) != nil
        else { return .malformed(.pem, .unreadable) }
        return .valid(.pem(.pkcs8, algorithm: nil, isEncrypted: true))
    }

    // MARK: - OIDs

    private static func ellipticCurve(oid: [UInt8]) -> EllipticCurve? {
        switch oid {
        case OID.secp256k1: .secp256k1
        case OID.p256: .p256
        case OID.p384: .p384
        case OID.p521: .p521
        case OID.curve25519Legacy: .curve25519
        default: nil
        }
    }

    /// The contents of each object identifier, as DER encodes them.
    private enum OID {
        /// 1.2.840.113549.1.1.1
        static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        /// 1.2.840.10040.4.1
        static let dsa: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x38, 0x04, 0x01]
        /// 1.2.840.10045.2.1
        static let ecPublicKey: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
        /// 1.3.101.112
        static let ed25519: [UInt8] = [0x2B, 0x65, 0x70]
        /// 1.3.101.113
        static let ed448: [UInt8] = [0x2B, 0x65, 0x71]
        /// 1.3.101.110
        static let x25519: [UInt8] = [0x2B, 0x65, 0x6E]
        /// 1.3.101.111
        static let x448: [UInt8] = [0x2B, 0x65, 0x6F]
        /// 1.3.132.0.10
        static let secp256k1: [UInt8] = [0x2B, 0x81, 0x04, 0x00, 0x0A]
        /// 1.2.840.10045.3.1.7
        static let p256: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
        /// 1.3.132.0.34
        static let p384: [UInt8] = [0x2B, 0x81, 0x04, 0x00, 0x22]
        /// 1.3.132.0.35
        static let p521: [UInt8] = [0x2B, 0x81, 0x04, 0x00, 0x23]
        /// 1.3.6.1.4.1.11591.15.1, OpenPGP's legacy Ed25519 (RFC 9580, section 9.2).
        static let ed25519Legacy: [UInt8] = [0x2B, 0x06, 0x01, 0x04, 0x01, 0xDA, 0x47, 0x0F, 0x01]
        /// 1.3.6.1.4.1.3029.1.5.1, OpenPGP's legacy Curve25519 for ECDH (RFC 9580, section 9.2).
        static let curve25519Legacy: [UInt8] = [0x2B, 0x06, 0x01, 0x04, 0x01, 0x97, 0x55, 0x01, 0x05, 0x01]
    }
}
