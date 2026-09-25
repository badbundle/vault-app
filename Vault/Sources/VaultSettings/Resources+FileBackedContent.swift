import Foundation

public final class FAQCodesFileContent: FileBackedContent {
    public let fileName: String = "FAQ-Codes"
    public let fileExtension: String = "md"

    public init() {}
}

public final class FAQBackupsGeneralFileContent: FileBackedContent {
    public let fileName: String = "FAQ-Backups-General"
    public let fileExtension: String = "md"

    public init() {}
}

public final class FAQBackupsSecurityFileContent: FileBackedContent {
    public let fileName: String = "FAQ-Backups-Security"
    public let fileExtension: String = "md"

    public init() {}
}

public final class BackupPasswordFileContent: FileBackedContent {
    public let fileName: String = "Backup-Password"
    public let fileExtension: String = "md"

    public init() {}
}

public final class BackupPasswordChangingFileContent: FileBackedContent {
    public let fileName: String = "Backup-Password-Changing"
    public let fileExtension: String = "md"

    public init() {}
}

public final class FAQItemEncryptionFileContent: FileBackedContent {
    public let fileName: String = "FAQ-Item-Encryption"
    public let fileExtension: String = "md"

    public init() {}
}

public final class FAQSyncDevicesFileContent: FileBackedContent {
    public let fileName: String = "FAQ-Sync-Devices"
    public let fileExtension: String = "md"

    public init() {}
}

public struct PrivacyPolicyContent: FileBackedContent {
    public let fileName: String = "PrivacyPolicy"
    public let fileExtension: String = "md"

    public init() {}
}

public struct TermsOfServiceContent: FileBackedContent {
    public let fileName: String = "TermsOfService"
    public let fileExtension: String = "md"

    public init() {}
}
