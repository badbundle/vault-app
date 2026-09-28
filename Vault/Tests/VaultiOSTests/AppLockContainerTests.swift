import Foundation
import SwiftUI
import TestHelpers
import Testing
import UIKit
import VaultSettings
@testable import VaultFeed
@testable import VaultiOS

/// `AppLockContainer` in a window, as the app has it: what it tells the lock about the scene, and what it builds of
/// the vault while the app is locked.
///
/// Serialized, as one test posts a notification every hosted container hears.
@MainActor
@Suite(.serialized)
struct AppLockContainerTests {
    @Test
    func sceneGoingToTheBackground_locksTheApp() async throws {
        let appLock = try makeAppLock()
        let scene = ScenePhaseModel()
        try host(appLock: appLock, scene: scene)
        // The prompt the app asks for as it becomes active passes.
        await appLock.automaticUnlock?.value
        #expect(!appLock.isLocked)

        scene.phase = .background

        try await waitUntil { appLock.isLocked }
    }

    /// Heard as soon as UIKit says the app is in the background, which SwiftUI's scene phase can lag behind.
    @Test
    func didEnterBackgroundNotification_locksTheApp() async throws {
        let appLock = try makeAppLock()
        try host(appLock: appLock)
        await appLock.automaticUnlock?.value
        #expect(!appLock.isLocked)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        try await waitUntil { appLock.isLocked }
    }

    /// Nothing of the vault is built behind the lock screen, and what was built goes when the app locks, its state
    /// with it: open details, decrypted notes and a typed search are all state of the views inside.
    @Test
    func content_isOnlyBuiltWhileUnlocked() async throws {
        let authentication = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        authentication.authenticateWithBiometricsHandler = { _ in false }
        let appLock = try makeAppLock(authentication: authentication, isEnabled: true)
        let scene = ScenePhaseModel()
        let content = ContentProbe()
        try host(appLock: appLock, scene: scene, content: content)
        // The prompt the app asks for as it becomes active fails.
        await appLock.automaticUnlock?.value
        #expect(appLock.isLocked)
        #expect(content.appearances == 0)

        authentication.authenticateWithBiometricsHandler = { _ in true }
        await appLock.unlock()
        try await waitUntil { content.appearances == 1 }
        #expect(content.model != nil)

        scene.phase = .background
        try await waitUntil { content.disappearances == 1 }
        try await waitUntil { content.model == nil }
        #expect(content.appearances == 1)
    }
}

// MARK: - Helpers

extension AppLockContainerTests {
    /// The scene phase the hosted container sees, which the test changes.
    @MainActor
    @Observable
    final class ScenePhaseModel {
        var phase = ScenePhase.active
    }

    /// Counts when the content is built and taken down, and keeps an eye on its state.
    @MainActor
    final class ContentProbe {
        var appearances = 0
        var disappearances = 0
        weak var model: ContentModel?
    }

    /// State of the content, which should go when the content does.
    final class ContentModel {}

    private struct ProbedContent: View {
        var probe: ContentProbe
        @State private var model = ContentModel()

        var body: some View {
            Color.clear
                .onAppear {
                    probe.appearances += 1
                    probe.model = model
                }
                .onDisappear {
                    probe.disappearances += 1
                }
        }
    }

    private struct Host: View {
        var appLock: AppLockService
        var localSettings: LocalSettings
        var scene: ScenePhaseModel
        var content: ContentProbe

        var body: some View {
            AppLockContainer(appLock: appLock, localSettings: localSettings) {
                ProbedContent(probe: content)
            }
            .environment(\.scenePhase, scene.phase)
        }
    }

    private func makeAppLock(
        authentication: any DeviceAuthenticationPolicy = .alwaysAllow,
        isEnabled: Bool = true,
    ) throws -> AppLockService {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.isEnabled = isEnabled
        settings.delay = .immediately
        return AppLockService(
            settings: settings,
            authenticationService: DeviceAuthenticationService(policy: authentication),
            purgeSensitiveData: {},
        )
    }

    /// Hosts the container in a window. The test runner has no scene to put one in, so this uses the window
    /// initializer that doesn't take a scene, deprecated as it is.
    @diagnose(DeprecatedDeclaration, as: ignored)
    private func host(
        appLock: AppLockService,
        scene: ScenePhaseModel = ScenePhaseModel(),
        content: ContentProbe = ContentProbe(),
    ) throws {
        let view = try Host(
            appLock: appLock,
            localSettings: LocalSettings(defaults: .nonPersistent()),
            scene: scene,
            content: content,
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        Self.windows.append(window)
    }

    /// Windows kept up for the rest of the run, as taking one down while SwiftUI is still updating it can crash.
    private static var windows = [UIWindow]()

    /// Waits for SwiftUI to catch up, up to a couple of seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
