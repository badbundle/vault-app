import AppKit
import Carbon.HIToolbox

/// Secure Keyboard Entry for one of Vault's fields (docs/mac-app.md, decision 8): on while the field has focus and
/// Vault is the active app, as AppKit's secure fields have it, so apps watching the keyboard see nothing typed into it.
///
/// It's off while another app is in front, even with the field still focused behind it, as it's for the whole Mac
/// while it's on, and on again once Vault is back, if the field still has focus. macOS counts each time it's turned
/// on across the process, so this only ever turns off what it turned on.
@MainActor
final class VaultMacSecureInput {
    /// Whether this has Secure Keyboard Entry on.
    private(set) var isOn = false
    /// Whether the field has focus.
    var hasFocus = false {
        didSet { update() }
    }

    private let isAppActive: @MainActor () -> Bool
    private let turnOn: @MainActor () -> Void
    private let turnOff: @MainActor () -> Void

    /// - Parameters:
    ///   - isAppActive: Whether Vault is the active app.
    ///   - turnOn: Turns Secure Keyboard Entry on, once more.
    ///   - turnOff: Turns it off, once.
    init(
        isAppActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive },
        turnOn: @escaping @MainActor () -> Void = { EnableSecureEventInput() },
        turnOff: @escaping @MainActor () -> Void = { DisableSecureEventInput() },
    ) {
        self.isAppActive = isAppActive
        self.turnOn = turnOn
        self.turnOff = turnOff
    }

    /// Vault became, or stopped being, the active app.
    func appActivityDidChange() {
        update()
    }

    private func update() {
        let shouldBeOn = hasFocus && isAppActive()
        guard shouldBeOn != isOn else { return }
        isOn = shouldBeOn
        if shouldBeOn {
            turnOn()
        } else {
            turnOff()
        }
    }
}
