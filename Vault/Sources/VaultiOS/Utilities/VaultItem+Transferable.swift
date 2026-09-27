import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import VaultFeed

/// A card in the feed is dragged to reorder it, as its ID.
///
/// It offers no text to another app: a code dropped there would skip the clipboard settings, as dragging selectable
/// text would (see `SelectableTextView`), and on an iPad it could reach another device over Universal Control whatever
/// Universal Clipboard allows. Tapping a code, or Copy Code, copies it through Vault's clipboard instead.
extension VaultItem: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.id)
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
