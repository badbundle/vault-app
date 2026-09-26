import Foundation
import SwiftUI
import UIKit
import VaultFeed

extension View {
    /// Shows `overlay` in a window of its own, above every other window in this view's scene, so it covers sheets,
    /// alerts and popovers too, which a SwiftUI overlay can't.
    ///
    /// The window is shown in the same update that sets `isPresented`. When `isPresented` goes back to `false`, the
    /// overlay can animate itself away: the window goes once the overlay calls the `didHide` it's given. Hidden, the
    /// overlay should keep showing what it would cover the scene with.
    ///
    /// SwiftUI hears that the scene has left the foreground too late for the app switcher's snapshot, so the window
    /// also shows as soon as UIKit says so, before any SwiftUI update, whenever `coversScene` says it should in that
    /// phase.
    func overlayWindow(
        isPresented: Bool,
        coversScene: @escaping (AppScenePhase) -> Bool,
        @ViewBuilder overlay: @escaping (_ didHide: @escaping () -> Void) -> some View,
    ) -> some View {
        background {
            OverlayWindowAnchor(isPresented: isPresented, coversScene: coversScene, overlay: overlay)
        }
    }
}

/// Finds the scene to put the window in, from its place in the view hierarchy.
private struct OverlayWindowAnchor<Overlay: View>: UIViewRepresentable {
    var isPresented: Bool
    var coversScene: (AppScenePhase) -> Bool
    var overlay: (_ didHide: @escaping () -> Void) -> Overlay

    func makeCoordinator() -> OverlayWindowPresenter<Overlay> {
        OverlayWindowPresenter()
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        let presenter = context.coordinator
        view.onMoveToWindow = { [weak presenter] window in
            presenter?.attach(to: window)
        }
        return view
    }

    func updateUIView(_: AnchorView, context: Context) {
        context.coordinator.update(isPresented: isPresented, coversScene: coversScene, overlay: overlay)
    }

    static func dismantleUIView(_: AnchorView, coordinator: OverlayWindowPresenter<Overlay>) {
        coordinator.detach()
    }

    final class AnchorView: UIView {
        var onMoveToWindow: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveToWindow?(window)
        }
    }
}

/// Owns the overlay's window: shows it as soon as it's presented, and hides it once the overlay has gone.
@MainActor
private final class OverlayWindowPresenter<Overlay: View> {
    private weak var hostWindow: UIWindow?
    private var window: UIWindow?
    private var hostingController: UIHostingController<Overlay>?
    private var isPresented = false
    /// Shown because the scene left the foreground, before SwiftUI asked for it.
    private var isShownAheadOfPresentation = false
    private var coversScene: (AppScenePhase) -> Bool = { _ in false }
    private var makeOverlay: ((_ didHide: @escaping () -> Void) -> Overlay)?
    private var sceneObservers = [any NSObjectProtocol]()

    func attach(to hostWindow: UIWindow?) {
        guard let hostWindow, hostWindow !== self.hostWindow else { return }
        detach()
        self.hostWindow = hostWindow
        observe(hostWindow.windowScene)
        apply()
    }

    func update(
        isPresented: Bool,
        coversScene: @escaping (AppScenePhase) -> Bool,
        overlay: @escaping (_ didHide: @escaping () -> Void) -> Overlay,
    ) {
        self.isPresented = isPresented
        self.coversScene = coversScene
        makeOverlay = overlay
        apply()
    }

    func detach() {
        for observer in sceneObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sceneObservers.removeAll()
        window?.isHidden = true
        window = nil
        hostingController = nil
    }

    private func apply() {
        guard let makeOverlay, let scene = hostWindow?.windowScene else { return }
        let overlay = makeOverlay { [weak self] in
            self?.overlayDidHide()
        }
        if let hostingController {
            hostingController.rootView = overlay
        } else if isPresented || coversScene(.background) {
            // Made the first time it might be needed, and kept ready: with the lock off, never.
            makeWindow(in: scene, showing: overlay)
        }

        if isPresented {
            isShownAheadOfPresentation = false
            show()
        }
    }

    private func makeWindow(in scene: UIWindowScene, showing overlay: Overlay) {
        let hostingController = UIHostingController(rootView: overlay)
        hostingController.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = hostingController
        window.isHidden = true
        self.hostingController = hostingController
        self.window = window
    }

    private func show() {
        guard let window, window.isHidden else { return }
        window.isHidden = false
        // Lay the overlay out now, so the window never shows a frame of what it showed last.
        hostingController?.view.layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func overlayDidHide() {
        guard !isPresented else { return }
        isShownAheadOfPresentation = false
        window?.isHidden = true
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    // MARK: - Scene lifecycle

    private func observe(_ scene: UIWindowScene?) {
        guard let scene else { return }
        let center = NotificationCenter.default
        // Delivered straight away, on the main thread, while UIKit moves the scene between states: ahead of the
        // snapshot the app switcher shows.
        sceneObservers = [
            center
                .addObserver(forName: UIScene.willDeactivateNotification, object: scene, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.sceneWillLeaveForeground(to: .inactive)
                    }
                },
            center
                .addObserver(
                    forName: UIScene.didEnterBackgroundNotification,
                    object: scene,
                    queue: nil,
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.sceneWillLeaveForeground(to: .background)
                    }
                },
            center.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sceneDidActivate()
                }
            },
        ]
    }

    private func sceneWillLeaveForeground(to phase: AppScenePhase) {
        guard !isPresented, coversScene(phase) else { return }
        if window == nil, let makeOverlay, let scene = hostWindow?.windowScene {
            makeWindow(in: scene, showing: makeOverlay { [weak self] in self?.overlayDidHide() })
        }
        isShownAheadOfPresentation = true
        show()
    }

    private func sceneDidActivate() {
        guard isShownAheadOfPresentation else { return }
        // Back before SwiftUI caught up with the scene leaving the foreground, it may never ask for the overlay, or
        // take it away. Once it's had the chance, take it down if it didn't.
        DispatchQueue.main.async { [weak self] in
            guard let self, isShownAheadOfPresentation, !isPresented else { return }
            isShownAheadOfPresentation = false
            window?.isHidden = true
        }
    }
}
