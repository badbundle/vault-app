import Foundation

/// Vault-scoped identifiers for specific pieces of data.
public enum VaultIdentifiers {
    public enum Item {
        public static let secureNote = "vault.item.secure-note.v1"
        public static let otpCode = "vault.item.otp-code.v1"
        /// Only ever stored inside an encrypted item, never as a plaintext payload.
        public static let recoveryPhrase = "vault.item.recovery-phrase.v1"
    }

    public enum SecureStorageKey {
        public static let backupPassword = "vault.secure-storage.backup-password.v1"
        /// HMAC key for per-item killphrase digests. Stored with
        /// `.whenUnlocked` access (no biometric) so the killphrase
        /// match path works as soon as the device is unlocked.
        public static let killphraseKey = "vault.secure-storage.killphrase-key.v1"
        /// HMAC key for per-item search-passphrase digests. Same access
        /// class as `killphraseKey` so the case-folded match works the
        /// moment the device is unlocked.
        public static let searchPassphraseKey = "vault.secure-storage.search-passphrase-key.v1"
    }

    public enum Backup {
        public static let encryptedVaultData = "vault.backup.encrypted-vault"
        public static let lastBackupEvent = "vault.backup.last-event"
    }

    public enum AutoBackup {
        public static let configuration = "vault.backup.auto.configuration"
    }

    public enum Preferences {
        public enum PDF {
            public static let defaultSize = "vault.preferences.pdf.default-size"
            public static let userHint = "vault.preferences.pdf.user-hint"
        }

        public enum General {
            public static let settingsPasteTTL = "vault.preferences.general.settings-paste-ttl"
        }

        public enum UniversalClipboard {
            public static let allowPasswords = "vault.preferences.universal-clipboard.allow-passwords"
            public static let allowOTPs = "vault.preferences.universal-clipboard.allow-otps"
            public static let allowOther = "vault.preferences.universal-clipboard.allow-other"
        }
    }

    public enum CodeScanning {
        public static let simulatedCode = "vault.codescanning.simulated-code"
    }
}
