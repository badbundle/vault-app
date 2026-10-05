import AppKit
import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultFeed
import VaultSettings
@testable import VaultMac

@MainActor
struct VaultMacCopierTests {
    @Test
    func copy_lockedCode_copiesOnlyOnceTheUserHasAuthenticated() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let action = VaultTextCopyAction(text: "123456", requiresAuthenticationToCopy: true, contentType: .otp)

        let denied = try await makeSUT(pasteboard: pasteboard, policy: DeviceAuthenticationPolicyAlwaysDeny())
            .copy(action)

        #expect(!denied)
        #expect(pasteboard.string(forType: .string) == nil)

        let allowed = try await makeSUT(pasteboard: pasteboard, policy: DeviceAuthenticationPolicyAlwaysAllow())
            .copy(action)

        #expect(allowed)
        #expect(pasteboard.string(forType: .string) == "123456")
    }

    @Test
    func copy_unlockedCode_copiesWithoutAsking() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let action = VaultTextCopyAction(text: "123456", requiresAuthenticationToCopy: false, contentType: .otp)

        let copied = try await makeSUT(pasteboard: pasteboard, policy: DeviceAuthenticationPolicyAlwaysDeny())
            .copy(action)

        #expect(copied)
        #expect(pasteboard.string(forType: .string) == "123456")
    }

    private func makeSUT(pasteboard: NSPasteboard, policy: some DeviceAuthenticationPolicy) throws -> VaultMacCopier {
        try VaultMacCopier(
            pasteboard: VaultMacPasteboard(
                system: NSPasteboardSystemPasteboard(pasteboard: pasteboard),
                localSettings: LocalSettings(defaults: .nonPersistent()),
                sleep: { _ in },
            ),
            authentication: DeviceAuthenticationService(policy: policy),
        )
    }
}
