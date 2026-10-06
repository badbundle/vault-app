import AppKit
import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultFeed
import VaultSettings
@testable import VaultMac

@MainActor
struct VaultMacPasteboardTests {
    @Test
    func copy_marksTheTextConcealedAndTransient() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let sut = NSPasteboardSystemPasteboard(pasteboard: pasteboard)

        _ = sut.copy(string: "123456", currentHostOnly: true)

        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.string(forType: .string) == "123456")
        #expect(item.types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")))
        #expect(item.types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")))
    }

    @Test
    func clear_onlyWhileNothingElseHasBeenCopied() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let sut = NSPasteboardSystemPasteboard(pasteboard: pasteboard)

        let copied = sut.copy(string: "123456", currentHostOnly: true)
        pasteboard.clearContents()
        pasteboard.setString("someone else's", forType: .string)
        sut.clear(ifStill: copied)

        #expect(pasteboard.string(forType: .string) == "someone else's")

        let copiedAgain = sut.copy(string: "654321", currentHostOnly: true)
        sut.clear(ifStill: copiedAgain)

        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test(arguments: PasteboardContentType.allCases)
    func copy_isLocalOnlyByDefault(contentType: PasteboardContentType) throws {
        let system = SystemPasteboardSpy()
        let sut = try makeSUT(system: system)

        sut.copy("text", as: contentType)

        #expect(system.copies.map(\.currentHostOnly) == [true])
    }

    @Test
    func copy_withUniversalClipboardAllowedForCodes_canReachOtherDevicesButDetailsStillCant() throws {
        let system = SystemPasteboardSpy()
        let settings = try LocalSettings(defaults: .nonPersistent())
        settings.state.allowUniversalClipboardForOTPs = true
        let sut = VaultMacPasteboard(system: system, localSettings: settings, sleep: { _ in })

        sut.copy("123456", as: .otp)
        sut.copy("account", as: .detail)

        #expect(system.copies.map(\.currentHostOnly) == [false, true])
    }

    @Test
    func copy_isClearedAfterTheClearClipboardTime() async throws {
        let system = SystemPasteboardSpy()
        let waits = WaitRecorder()
        let settings = try LocalSettings(defaults: .nonPersistent())
        let sut = VaultMacPasteboard(system: system, localSettings: settings, sleep: { await waits.record($0) })

        sut.copy("123456", as: .otp)
        await sut.pendingClear?.value

        #expect(await waits.durations == [.seconds(60)])
        #expect(system.clears == [system.copies.last?.contents])
    }

    @Test
    func copy_withClearClipboardNever_isNeverCleared() throws {
        let system = SystemPasteboardSpy()
        let settings = try LocalSettings(defaults: .nonPersistent())
        settings.state.pasteTimeToLive = .init(duration: nil)
        let sut = VaultMacPasteboard(system: system, localSettings: settings, sleep: { _ in })

        sut.copy("123456", as: .otp)

        #expect(sut.pendingClear == nil)
        #expect(system.clears.isEmpty)
    }

    @Test
    func clearNow_clearsWhatVaultCopied() throws {
        let system = SystemPasteboardSpy()
        let sut = try makeSUT(system: system)

        sut.copy("123456", as: .otp)
        sut.clearNow()

        #expect(system.clearedIfStillCopiedByVault == 1)
    }

    private func makeSUT(system: SystemPasteboardSpy) throws -> VaultMacPasteboard {
        try VaultMacPasteboard(
            system: system,
            localSettings: LocalSettings(defaults: .nonPersistent()),
            sleep: { _ in },
        )
    }
}

@MainActor
private final class SystemPasteboardSpy: VaultMacSystemPasteboard {
    struct Copy {
        var string: String
        var currentHostOnly: Bool
        var contents: VaultMacPasteboardContents
    }

    private(set) var copies = [Copy]()
    private(set) var clears = [VaultMacPasteboardContents]()
    private(set) var clearedIfStillCopiedByVault = 0

    func copy(string: String, currentHostOnly: Bool) -> VaultMacPasteboardContents {
        let contents = VaultMacPasteboardContents(changeCount: copies.count + 1)
        copies.append(Copy(string: string, currentHostOnly: currentHostOnly, contents: contents))
        return contents
    }

    func clear(ifStill contents: VaultMacPasteboardContents) {
        clears.append(contents)
    }

    func clearIfStillCopiedByVault() {
        clearedIfStillCopiedByVault += 1
    }
}

private actor WaitRecorder {
    private(set) var durations = [Duration]()

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}
