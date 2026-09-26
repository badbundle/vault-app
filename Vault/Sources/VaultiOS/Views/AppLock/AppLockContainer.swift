import Foundation
import SwiftUI
import UIKit
import VaultFeed
import VaultSettings

/// Keeps the vault behind the app lock, and out of screen recordings.
///
/// Nothing of `content` is built while the app is locked, and a window of its own covers everything else in the
/// scene, sheets included: the lock screen while the app is locked, otherwise whichever `AppCover` the scene needs.
/// That's the privacy cover whenever the lock is on and the app isn't in the foreground, and the screen capture cover
/// while the screen is recorded, mirrored or shared (unless the user has turned that off). Without either, this is
/// just `content`.
struct AppLockContainer<Content: View>: View {
    var appLock: AppLockService
    var localSettings: LocalSettings
    @ViewBuilder var content: () -> Content

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured

    var body: some View {
        ZStack {
            if appLock.isLocked {
                AppPrivacyCoverView()
            } else {
                content()
            }
        }
        .overlayWindow(
            isPresented: appLock.isLocked || cover != nil,
            coversScene: { phase in cover(in: phase) != nil },
            overlay: { didHide in
                AppLockShieldView(appLock: appLock, cover: cover, didHide: didHide)
            },
        )
        .onChange(of: scenePhase, initial: true) { _, phase in
            appLock.scenePhaseDidChange(to: AppScenePhase(phase))
        }
        // Heard as soon as the app is in the background, which SwiftUI's scene phase can lag behind.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            appLock.scenePhaseDidChange(to: .background)
        }
    }

    private var cover: AppCover? {
        cover(in: AppScenePhase(scenePhase))
    }

    private func cover(in phase: AppScenePhase) -> AppCover? {
        AppCover.required(
            isPrivacyCoverRequired: appLock.requiresPrivacyCover(in: phase),
            hidesVaultWhileScreenCaptured: localSettings.state.hidesVaultWhileScreenCaptured,
            isScreenCaptured: isSceneCaptured,
        )
    }
}

/// What the app lock's window shows: the lock screen while the app is locked, and the door opening once it's
/// unlocked; otherwise the `cover`.
///
/// Appears at once, so nothing shows before it, and fades away when it's no longer needed. Once it's gone it goes
/// back to showing the privacy cover, ready for the window to show again the moment the app leaves the foreground.
struct AppLockShieldView: View {
    var appLock: AppLockService
    /// What the scene needs covering with, as well as any lock screen.
    var cover: AppCover?
    /// Called once it has faded away, so the window can go.
    var didHide: () -> Void

    /// The lock screen as it last was, for the door to open on after the app unlocks.
    @State private var lockedState = AppLockedState(step: .deviceAuthentication)
    /// Just unlocked: the lock screen stays for its door to open, and until it has faded away.
    @State private var isRevealing = false
    /// The door has opened: the vault can come in once nothing needs covering.
    @State private var hasOpened = false
    /// The cover last asked for, kept on screen while it fades away.
    @State private var shownCover = AppCover.privacy
    @State private var isShowing = true

    var body: some View {
        ZStack {
            if appLock.isLocked || isRevealing {
                AppLockView(
                    state: currentLockedState,
                    isOpening: isRevealing,
                    onOpened: doorDidOpen,
                    unlock: { await appLock.unlock() },
                    unlockWithPassword: { await appLock.unlock(password: $0) },
                )
            } else {
                switch shownCover {
                case .privacy:
                    AppPrivacyCoverView()
                case .screenCapture:
                    AppScreenCaptureCoverView()
                }
            }
        }
        // Fully shown while it's needed, whatever an earlier fade left it at.
        .opacity(appLock.isLocked || cover != nil || isShowing ? 1 : 0)
        .onChange(of: appLock.state, initial: true) { oldState, newState in
            if case let .locked(locked) = newState {
                // Without its progress or failure: the door opens on a settled lock screen.
                lockedState = AppLockedState(step: locked.step)
                isRevealing = false
                hasOpened = false
                showAtOnce()
            } else if case .locked = oldState {
                isRevealing = true
                hasOpened = false
                showAtOnce()
            }
        }
        .onChange(of: cover, initial: true) { _, cover in
            coverDidChange(to: cover)
        }
    }

    private var currentLockedState: AppLockedState {
        if case let .locked(locked) = appLock.state {
            locked
        } else {
            lockedState
        }
    }

    private func coverDidChange(to cover: AppCover?) {
        if let cover {
            withTransaction(Transaction(animation: nil)) {
                shownCover = cover
            }
            showAtOnce()
            // Unlocked while being recorded: the capture cover takes over from the opened door.
            if cover == .screenCapture, hasOpened {
                finishRevealing()
            }
        } else if !appLock.isLocked, !isRevealing || hasOpened {
            hide()
        }
    }

    private func showAtOnce() {
        withTransaction(Transaction(animation: nil)) {
            isShowing = true
        }
    }

    private func doorDidOpen() {
        hasOpened = true
        switch cover {
        case nil:
            hide()
        case .screenCapture:
            finishRevealing()
        case .privacy:
            // Still under the Face ID prompt, it waits for the app to come back to the foreground.
            break
        }
    }

    private func finishRevealing() {
        withAnimation(.easeOut(duration: 0.3)) {
            isRevealing = false
            hasOpened = false
        }
    }

    private func hide() {
        withAnimation(.easeOut(duration: 0.3)) {
            isShowing = false
        } completion: {
            // Shown again while it faded: it's still needed.
            guard !isShowing, !appLock.isLocked else { return }
            didHide()
            // Ready for next time, out of sight.
            isRevealing = false
            hasOpened = false
            shownCover = .privacy
            showAtOnce()
        }
    }
}

extension AppScenePhase {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default: self = .inactive
        }
    }
}
