import AppKit
import Testing

/// The Mac app, launched as it ships, with these tests running inside it.
@MainActor
struct MacAppLaunchTests {
    @Test
    func launch_opensTheMainWindowTitledOnlyVault() async throws {
        let window = try await mainWindow()

        #expect(window.title == "Vault")
    }

    @Test
    func launch_runsInTheAppSandbox() {
        #expect(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
    }

    @Test
    func appGroupContainer_isTheTeamPrefixedOne() {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)

        #expect(container?.lastPathComponent == Self.appGroupID)
    }

    /// Hide While Recording is on by default (G24, C7), so no window can be captured, and none is restored.
    @Test
    func launch_everyWindowIsHiddenFromCaptureAndNeverRestored() async throws {
        _ = try await mainWindow()

        for window in NSApp.windows where window.isVisible {
            #expect(window.sharingType == .none, "\(window.title)")
            #expect(!window.isRestorable, "\(window.title)")
            #expect(window.tabbingMode == .disallowed, "\(window.title)")
        }
    }

    /// Nothing from Vault is offered to Handoff or the Services menu.
    @Test
    func app_offersNoHandoffOrServices() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") == nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSServices") == nil)
        #expect(NSApp.servicesProvider == nil)
    }

    /// docs/mac-app.md, decision 7.
    static let appGroupID = "442P244AFS.com.badbundle.vault"

    /// The main window, once the app has put it on screen.
    private func mainWindow() async throws -> NSWindow {
        for _ in 0 ..< 100 {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
                return window
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The main window never opened. Windows: \(NSApp.windows.map(\.title))")
        throw CancellationError()
    }
}
