import AppKit
import Combine
import SwiftUI
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed
@testable import VaultMac

@MainActor
struct VaultMacFeedSnapshotTests {
    @Test(arguments: MacAppearance.allCases)
    func list(appearance: MacAppearance) {
        let items = [
            MacTestItems.code(issuer: "Example", account: "ada@example.com"),
            MacTestItems.code(
                issuer: "Locked Site",
                account: "grace@example.com",
                lockState: .lockedWithNativeSecurity,
            ),
            MacTestItems.code(issuer: "Counter", account: "alan@example.com", type: .hotp(counter: 3)),
            MacTestItems.note(),
        ]
        let view = List(items) { item in
            VaultMacItemRow(item: item, showsNextCode: false, copiesOnClick: true)
        }
        .environment(\.vaultMacItemPreviews, .fixed)

        assertSnapshot(
            of: view,
            as: .macWindow(width: 360, height: 280, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    @Test(arguments: MacAppearance.allCases)
    func codePage(appearance: MacAppearance) {
        let view = detail(MacTestItems.code(issuer: "Example", account: "ada@example.com"))

        assertSnapshot(
            of: view,
            as: .macWindow(width: 620, height: 420, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    @Test(arguments: MacAppearance.allCases)
    func notePage(appearance: MacAppearance) {
        let view = detail(MacTestItems.note(
            title: "Recovery Codes",
            contents: "# Codes\n\n- 1234-5678\n- 8765-4321\n\nKeep these **safe**.",
            format: .markdown,
        ))

        assertSnapshot(
            of: view,
            as: .macWindow(width: 620, height: 420, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    @Test
    func lockedPage_showsNothingOfTheItem() {
        let view = detail(MacTestItems.code(issuer: "Secret Site", lockState: .lockedWithNativeSecurity))

        assertSnapshot(of: view, as: .macWindow(width: 620, height: 420))
    }

    @Test
    func recoveryPhrase_wordsMasked() {
        let phrase = RecoveryPhrase(
            title: "Wallet",
            words: [
                "abandon",
                "ability",
                "able",
                "about",
                "above",
                "absent",
                "absorb",
                "abstract",
                "absurd",
                "abuse",
                "access",
                "accident",
            ],
            standard: .bip39,
            passphrase: "",
            contents: "The hardware wallet in the drawer.",
        )
        let view = VaultMacRecoveryPhraseDetailView(
            phrase: phrase,
            metadata: MacTestItems.metadata(),
            tags: [],
            encryptionKey: DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing),
        )
        .padding(28)

        assertSnapshot(of: view, as: .macWindow(width: 620, height: 420))
    }

    private func detail(_ item: VaultItem) -> some View {
        VaultMacItemDetailView(
            item: item,
            tags: [],
            authentication: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            keyDeriverFactory: VaultKeyDeriverFactoryImpl(),
        )
        .environment(\.vaultMacItemPreviews, .fixed)
    }
}

extension VaultMacItemPreviews {
    /// Codes that never change: 123 456 for every code, its timer stopped.
    static var fixed: VaultMacItemPreviews {
        VaultMacItemPreviews(
            totp: { metadata, code in fixedViewModel(metadata: metadata, data: code.data) },
            hotp: { metadata, code in fixedViewModel(metadata: metadata, data: code.data) },
            timer: { _ in OTPCodeTimerPeriodState(statePublisher: Empty().eraseToAnyPublisher()) },
            incrementer: { _, _ in nil },
        )
    }

    private static func fixedViewModel(metadata: VaultItem.Metadata, data: OTPAuthCodeData) -> OTPCodePreviewViewModel {
        OTPCodePreviewViewModel(
            accountName: data.accountName,
            issuer: data.issuer,
            color: metadata.color ?? .default,
            isLocked: metadata.lockState.isLocked,
            fixedCodeState: metadata.lockState.isLocked ? .locked(code: "123456") : .visible("123456"),
        )
    }
}
