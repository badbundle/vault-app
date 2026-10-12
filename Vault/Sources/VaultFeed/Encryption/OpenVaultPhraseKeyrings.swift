import Foundation
import FoundationExtensions

/// The killphrase and search passphrase keyrings of whichever vault is open, wherever it keeps them
/// (`VaultPhraseKeyrings`):
///
/// - **The plain store's** are this device's, in the keychain (`DevicePhraseKeyrings`), where they've always been.
/// - **An encrypted vault the App Lock Password opens** keeps its own in its payload, so they move with the vault
///   file. A vault made before vaults kept their own has none there the first time it opens: it takes a copy of this
///   device's then, with a new key of its own (`VaultPhraseKeyrings.takingCopies`), and saves it before any of it is
///   used. This device's stay, as another vault made then may not have opened yet,
///   and a vault can't tell whether there are others. If the copy can't be saved, the vault uses this device's
///   keyrings for now, which are kept, and it's tried again the next time they're read. So no key is ever lost: a
///   lost key would quietly stop the phrases it checks working (MANIFESTO).
/// - **An encrypted vault the device key opens**, while the password is off, keeps them in the keychain, as turning
///   the password off left them (`VaultPasswordChangeService`), or this device's, if it was turned off before vaults
///   kept their own.
/// - **While the vault is locked** there are none.
///
/// Each vault's are its own, so a duress vault never holds the keys that check another vault's phrases, and a backup
/// of one carries only its own. `VaultDataModel` reads them through `killphraseKeys` and `searchPassphraseKeys`, and
/// reads them again whenever the open vault changes. Never log, print or measure which vault is open, or anything
/// about its keys (MANIFESTO C3).
public final class OpenVaultPhraseKeyrings: Sendable {
    private let session: VaultStoreSession
    private let device: DevicePhraseKeyrings

    /// - Parameters:
    ///   - session: The store session, whose open vault these are the keyrings of.
    ///   - device: The keyrings in this device's keychain.
    public init(session: VaultStoreSession, device: DevicePhraseKeyrings) {
        self.session = session
        self.device = device
    }

    /// The open vault's killphrase keyring, for `KillphraseDigester`.
    public var killphraseKeys: some KillphraseKeyStore<KeyData<32>> {
        KillphraseKeys(keyrings: self)
    }

    /// The open vault's search passphrase keyring, for `SearchPassphraseDigester`.
    public var searchPassphraseKeys: some SearchPassphraseKeyStore<KeyData<32>> {
        SearchPassphraseKeys(keyrings: self)
    }
}

// MARK: - Keys

extension OpenVaultPhraseKeyrings {
    /// The open vault's own key for `kind`, which makes every new digest. The plain store's is made and stored the
    /// first time it's needed.
    ///
    /// - Throws: `VaultStoreSessionError.locked` while the vault is locked, or an error reading the keychain.
    func ownKey(_ kind: VaultPhraseKeyrings.Kind) async throws -> KeyData<32> {
        switch try await location() {
        case let .vault(keyrings): keyrings[kind].ownKey
        case .device: try await device.keyring(kind).loadOrCreateOwnKey()
        }
    }

    /// The keys of `kind` the open vault only matches against: those restored backups brought, and those its
    /// phrases were digested with before it had keys of its own.
    func keysFromBackups(_ kind: VaultPhraseKeyrings.Kind) async throws -> [KeyData<32>] {
        switch try await location() {
        case let .vault(keyrings): keyrings[kind].keysFromBackups
        case .device: try await device.keyring(kind).loadKeysFromBackups()
        }
    }

    /// Adds the keys a restored backup brought to the open vault's keyring of `kind`, wherever it keeps it.
    ///
    /// - Throws: If they can't be added, as when the vault's payload can't be saved. Then nothing's changed.
    func addKeysFromBackup(_ keys: [KeyData<32>], to kind: VaultPhraseKeyrings.Kind) async throws {
        guard keys.isNotEmpty else { return }
        switch await session.openVault {
        case .locked:
            throw VaultStoreSessionError.locked
        case .plain:
            try await device.keyring(kind).addKeysFromBackup(keys)
        case let .encrypted(store):
            if await !store.opensWithTheDeviceKey {
                // A vault that has none takes its copy of this device's in the same save.
                let copies = await store.phraseKeyrings == nil ? try await device.copiesForAVault() : nil
                let saved = try await session.whileOpen(.encrypted(store)) {
                    try await store.updatePhraseKeyrings { current in
                        // Only turning the password off takes them out of a payload, and then nothing is updated.
                        guard var keyrings = current ?? copies else { throw VaultStoreSessionError.locked }
                        keyrings[kind].add(keys)
                        return keyrings
                    }
                }
                if saved != nil {
                    return
                }
            }
            try await addKeysWhilePasswordIsOff(keys, to: kind)
        }
    }

    private func addKeysWhilePasswordIsOff(_ keys: [KeyData<32>], to kind: VaultPhraseKeyrings.Kind) async throws {
        if var keyrings = try await device.passwordOffKeyrings() {
            guard keyrings[kind].add(keys) else { return }
            try await device.storePasswordOffKeyrings(keyrings)
        } else {
            try await device.keyring(kind).addKeysFromBackup(keys)
        }
    }
}

// MARK: - Delete All Data

/// Deletes the keyrings in the keychain that no vault can need once Delete All Data has emptied the open vault and
/// destroyed every other one (`VaultDataModel.deleteVault()`).
public protocol PhraseKeyringsCleanup: Sendable {
    func deleteKeyringsNoOtherVaultNeeds() async throws
}

extension OpenVaultPhraseKeyrings: PhraseKeyringsCleanup {
    /// Once Delete All Data has destroyed every vault but the open one, this device's keyrings only served vaults
    /// that are gone, if the open vault keeps its own elsewhere: in its payload, or, with the password off, where
    /// turning it off left them. They're deleted then, and so are keyrings a turn off left behind that the open vault
    /// isn't using. Keyrings the open vault still uses stay: the plain store's, and those of a vault that hasn't taken
    /// its copy yet.
    public func deleteKeyringsNoOtherVaultNeeds() async throws {
        guard case let .encrypted(store) = await session.openVault else { return }
        if await store.opensWithTheDeviceKey {
            guard try await device.passwordOffKeyrings() != nil else { return }
            try await device.delete()
        } else {
            guard await store.phraseKeyrings != nil else { return }
            try await device.delete()
            try await device.deletePasswordOffKeyrings()
        }
    }
}

// MARK: - Where they are

extension OpenVaultPhraseKeyrings {
    /// Where the open vault's keyrings are.
    private enum Location {
        /// Its own: those in its payload, or those turning the password off moved to the keychain.
        case vault(VaultPhraseKeyrings)
        /// This device's, in the keychain (`HMACKeyring`).
        case device
    }

    /// Where the open vault's keyrings are, after taking a copy of this device's into a vault that has none.
    private func location() async throws -> Location {
        switch await session.openVault {
        case .locked:
            throw VaultStoreSessionError.locked
        case .plain:
            return .device
        case let .encrypted(store):
            if await store.opensWithTheDeviceKey {
                return try await locationWhilePasswordIsOff()
            }
            if let keyrings = await store.phraseKeyrings {
                return .vault(keyrings)
            }
            return try await takeCopies(into: store)
        }
    }

    private func locationWhilePasswordIsOff() async throws -> Location {
        try await device.passwordOffKeyrings().map { .vault($0) } ?? .device
    }

    /// Gives a vault made before vaults kept their own keyrings of its own, from this device's, saved in its payload
    /// before any of it is used. This device's are kept.
    ///
    /// If they can't be saved, the vault uses this device's keyrings for now, which hold every key the copy would, and
    /// it's tried again the next time its keyrings are read: the next unlock, a backup, or a restore.
    private func takeCopies(into store: EncryptedVaultStore) async throws -> Location {
        let copies = try await device.copiesForAVault()
        let saved: VaultPhraseKeyrings?
        do {
            saved = try await session.whileOpen(.encrypted(store)) {
                try await store.updatePhraseKeyrings { $0 ?? copies }
            }
        } catch {
            return .device
        }
        guard let saved else {
            // The password was turned off meanwhile.
            return try await locationWhilePasswordIsOff()
        }
        return .vault(saved)
    }
}

// MARK: - Key stores

extension OpenVaultPhraseKeyrings {
    /// The open vault's killphrase keyring, as `VaultDataModel` reads it.
    private struct KillphraseKeys: KillphraseKeyStore {
        let keyrings: OpenVaultPhraseKeyrings

        func loadOrCreate() async throws -> KeyData<32> {
            try await keyrings.ownKey(.killphrase)
        }

        func loadKeysFromBackups() async throws -> [KeyData<32>] {
            try await keyrings.keysFromBackups(.killphrase)
        }

        func addKeysFromBackup(_ keys: [KeyData<32>]) async throws {
            try await keyrings.addKeysFromBackup(keys, to: .killphrase)
        }
    }

    /// The open vault's search passphrase keyring, as `VaultDataModel` reads it.
    private struct SearchPassphraseKeys: SearchPassphraseKeyStore {
        let keyrings: OpenVaultPhraseKeyrings

        func loadOrCreate() async throws -> KeyData<32> {
            try await keyrings.ownKey(.searchPassphrase)
        }

        func loadKeysFromBackups() async throws -> [KeyData<32>] {
            try await keyrings.keysFromBackups(.searchPassphrase)
        }

        func addKeysFromBackup(_ keys: [KeyData<32>]) async throws {
            try await keyrings.addKeysFromBackup(keys, to: .searchPassphrase)
        }
    }
}

// MARK: - None

/// Key stores for a process that never checks phrases, the AutoFill extensions (G2, G47): every call throws, so it
/// can't read the keychain's keyrings, make keys, or save a copy into a vault it opened. Its data model never loads
/// them, and this keeps it that way: an extension reading another keychain group could otherwise give a vault made
/// before vaults kept their own a copy without the keys its phrases were digested with.
public enum NoPhraseKeyrings {
    public struct Unavailable: Error, Equatable {}

    public static var killphraseKeys: some KillphraseKeyStore<KeyData<32>> {
        KillphraseKeys()
    }

    public static var searchPassphraseKeys: some SearchPassphraseKeyStore<KeyData<32>> {
        SearchPassphraseKeys()
    }

    private struct KillphraseKeys: KillphraseKeyStore {
        func loadOrCreate() async throws -> KeyData<32> {
            throw Unavailable()
        }

        func loadKeysFromBackups() async throws -> [KeyData<32>] {
            throw Unavailable()
        }

        func addKeysFromBackup(_: [KeyData<32>]) async throws {
            throw Unavailable()
        }
    }

    private struct SearchPassphraseKeys: SearchPassphraseKeyStore {
        func loadOrCreate() async throws -> KeyData<32> {
            throw Unavailable()
        }

        func loadKeysFromBackups() async throws -> [KeyData<32>] {
            throw Unavailable()
        }

        func addKeysFromBackup(_: [KeyData<32>]) async throws {
            throw Unavailable()
        }
    }
}
