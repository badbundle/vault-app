import Foundation
import SwiftUI
import UIKit
import VaultFeed

/// Keeps the vault behind the app lock.
///
/// Nothing of `content` is built while the app is locked, and a window of its own covers everything else in the
/// scene, sheets included: the lock screen while the app is locked, and the privacy cover whenever the lock is on and
/// the app isn't in the foreground. With the lock off, this is just `content`.
struct AppLockContainer<Content: View>: View {
    var appLock: AppLockService
    @ViewBuilder var content: () -> Content

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if appLock.isLocked {
                AppPrivacyCoverView()
            } else {
                content()
            }
        }
        .overlayWindow(
            isPresented: appLock.isLocked || isCoverRequired,
            coversScene: { phase in appLock.requiresPrivacyCover(in: phase) },
            overlay: { didHide in
                AppLockShieldView(appLock: appLock, isCoverRequired: isCoverRequired, didHide: didHide)
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

    private var isCoverRequired: Bool {
        appLock.requiresPrivacyCover(in: AppScenePhase(scenePhase))
    }
}

/// What the app lock's window shows: the lock screen while the app is locked, and the door opening once it's
/// unlocked; otherwise the privacy cover.
///
/// Appears at once, so nothing shows before it, and fades away when it's no longer needed. Once it's gone it goes
/// back to showing the privacy cover, ready for the window to show again the moment the app leaves the foreground.
struct AppLockShieldView: View {
    var appLock: AppLockService
    var isCoverRequired: Bool
    /// Called once it has faded away, so the window can go.
    var didHide: () -> Void

    /// The lock screen as it last was, for the door to open on after the app unlocks.
    @State private var lockedState = AppLockedState(step: .deviceAuthentication)
    /// Just unlocked: the lock screen stays for its door to open, and until it has faded away.
    @State private var isRevealing = false
    /// The door has opened: the vault can come in once the app is in the foreground.
    @State private var hasOpened = false
    @State private var isShowing = true

    var body: some View {
        ZStack {
            if appLock.isLocked || isRevealing {
                AppLockView(
                    state: currentLockedState,
                    isOpening: isRevealing,
                    onOpened: doorDidOpen,
                    unlock: { await appLock.unlock() },
                )
            } else {
                AppPrivacyCoverView()
            }
        }
        // Fully shown while it's needed, whatever an earlier fade left it at.
        .opacity(appLock.isLocked || isCoverRequired || isShowing ? 1 : 0)
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
        .onChange(of: isCoverRequired) { _, isCoverRequired in
            if isCoverRequired {
                showAtOnce()
            } else if !appLock.isLocked, !isRevealing || hasOpened {
                hide()
            }
        }
    }

    private var currentLockedState: AppLockedState {
        if case let .locked(locked) = appLock.state {
            locked
        } else {
            lockedState
        }
    }

    private func showAtOnce() {
        withTransaction(Transaction(animation: nil)) {
            isShowing = true
        }
    }

    private func doorDidOpen() {
        hasOpened = true
        // Still under the Face ID prompt, it waits for the app to come back to the foreground.
        if !isCoverRequired {
            hide()
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
