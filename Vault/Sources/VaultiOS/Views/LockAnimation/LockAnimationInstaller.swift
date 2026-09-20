import SwiftUI
import WindowOverlay

extension View {
    /// Hosts the lock animation for this window and hands its presenter to the
    /// environment below.
    ///
    /// The animation gets its own `UIWindow` (through `WindowOverlay`, the same
    /// mechanism the toasts use) because the item detail is a sheet: a plain
    /// overlay on the root view would draw underneath it.
    func installLockAnimation(_ presenter: LockAnimationPresenter) -> some View {
        modifier(LockAnimationInstaller(presenter: presenter))
    }
}

private struct LockAnimationInstaller: ViewModifier {
    var presenter: LockAnimationPresenter

    func body(content: Content) -> some View {
        content
            .windowOverlay(isPresented: presenter.current != nil, disableSafeArea: true) {
                LockAnimationOverlayView(presenter: presenter)
            }
            .environment(presenter)
    }
}
