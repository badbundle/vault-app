import Foundation
import FoundationExtensions
import VaultCore
@testable import VaultFeed

/// Items for the Mac's tests, the same every run.
enum MacTestItems {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    static func metadata(
        id: Identifier<VaultItem> = .new(),
        userDescription: String = "",
        tags: Set<Identifier<VaultItemTag>> = [],
        lockState: VaultItemLockState = .notLocked,
        color: VaultItemColor? = nil,
        previewMode: NotePreviewMode = .titleAndFirstLine,
    ) -> VaultItem.Metadata {
        .init(
            id: id,
            created: date,
            updated: date,
            relativeOrder: .min,
            userDescription: userDescription,
            tags: tags,
            visibility: .always,
            searchableLevel: .full,
            searchPassphrase: nil,
            killphrase: nil,
            lockState: lockState,
            color: color,
            showInQuickType: true,
            previewMode: previewMode,
        )
    }

    static func code(
        issuer: String = "Example",
        account: String = "ada@example.com",
        type: OTPAuthType = .totp(),
        lockState: VaultItemLockState = .notLocked,
        tags: Set<Identifier<VaultItemTag>> = [],
    ) -> VaultItem {
        VaultItem(
            metadata: metadata(tags: tags, lockState: lockState),
            item: .otpCode(OTPAuthCode(
                type: type,
                data: .init(
                    secret: .init(data: Data(repeating: 0x42, count: 20), format: .base32),
                    accountName: account,
                    issuer: issuer,
                ),
            )),
        )
    }

    static func note(
        title: String = "Wi-Fi",
        contents: String = "The router's password is under the stand.",
        format: TextFormat = .plain,
        tags: Set<Identifier<VaultItemTag>> = [],
    ) -> VaultItem {
        VaultItem(
            metadata: metadata(userDescription: "The router's password is under the stand.", tags: tags),
            item: .secureNote(SecureNote(title: title, contents: contents, format: format)),
        )
    }
}
