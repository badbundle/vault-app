import Foundation
import SwiftUI
import VaultFeed

struct DeveloperCreateItemsView: View {
    @Environment(VaultDataModel.self) var dataModel

    var body: some View {
        Form {
            AsyncButton {
                let factory = VaultItemDemoFactory()
                let hotpItem = factory.makeHOTPCode()
                try await dataModel.insert(item: hotpItem)
            } label: {
                Text("Create HOTP")
            } loading: {
                ProgressView()
            }

            AsyncButton {
                let factory = VaultItemDemoFactory()
                let item = factory.makeTOTPCode()
                try await dataModel.insert(item: item)
            } label: {
                Text("Create TOTP")
            } loading: {
                ProgressView()
            }

            AsyncButton {
                let factory = VaultItemDemoFactory()
                let item = factory.makeSecureNote()
                try await dataModel.insert(item: item)
            } label: {
                Text("Create note")
            } loading: {
                ProgressView()
            }

            AsyncButton {
                let factory = VaultItemDemoFactory()
                let item = try factory.makeEncryptedSecureNote()
                try await dataModel.insert(item: item)
            } label: {
                Text("Create encrypted note")
            } loading: {
                ProgressView()
            }

            AsyncButton {
                let factory = VaultItemDemoFactory()
                let item = try factory.makeEncryptedRecoveryPhrase()
                try await dataModel.insert(item: item)
            } label: {
                Text("Create encrypted recovery phrase")
            } loading: {
                ProgressView()
            }
        }
    }
}
