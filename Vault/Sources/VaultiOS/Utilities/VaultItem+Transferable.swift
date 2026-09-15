import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import VaultFeed

private enum VaultItemTransferError: Error {
    case unableToCreateString
}

extension VaultItem: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        MainActor.assumeIsolated {
            VaultSharingContentTransferRepresentation(copyActionHandler: VaultRoot.vaultItemCopyHandler)
        }
    }

    public struct VaultSharingContentTransferRepresentation<C: VaultItemCopyActionHandler>: TransferRepresentation {
        public typealias Item = VaultItem
        private let copyActionHandler: C

        init(copyActionHandler: C) {
            self.copyActionHandler = copyActionHandler
        }

        public var body: some TransferRepresentation {
            DataRepresentation(exportedContentType: .plainText) { item in
                guard
                    let data = await copyActionHandler.textToCopyForVaultItem(id: item.id),
                    !data.requiresAuthenticationToCopy
                else {
                    return Data()
                }
                if let string = data.text.data(using: .utf8) {
                    return string
                } else {
                    throw VaultItemTransferError.unableToCreateString
                }
            }
            ProxyRepresentation(exporting: \.id)
        }
    }
}

private enum VaultIDTransferError: Error {
    case idDecodingError
}

struct VaultIDTransferRepresentation: TransferRepresentation {
    typealias Item = Identifier<VaultItem>

    var body: some TransferRepresentation {
        DataRepresentation(contentType: .vaultIdentifierItemType) { id in
            Data(id.id.uuidString.bytes)
        } importing: { data in
            let string = String(decoding: data, as: Unicode.UTF8.self)
            guard let uuid = UUID(uuidString: string) else { throw VaultIDTransferError.idDecodingError }
            return Identifier(id: uuid)
        }
    }
}

extension Identifier: Transferable where T == VaultItem {
    public static var transferRepresentation: some TransferRepresentation {
        VaultIDTransferRepresentation()
    }
}

extension UTType {
    /// importedAs, not exportedAs: this code is evaluated in every bundle
    /// that links VaultiOS (main app AND the autofill extension), but only
    /// the main app exports the type declaration. `exportedAs` raises a
    /// runtime fault when the calling bundle does not declare the type.
    static let vaultIdentifierItemType = UTType(importedAs: "vault.identifier.drop.id", conformingTo: .data)
}
