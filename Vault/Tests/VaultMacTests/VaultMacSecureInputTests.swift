import Testing
@testable import VaultMac

/// Secure Keyboard Entry is on while a field has focus and Vault is the active app, as AppKit's secure fields have it,
/// and only then: it's for the whole Mac while it's on (docs/mac-app.md, decision 8).
@MainActor
struct VaultMacSecureInputTests {
    @Test
    func focus_whileVaultIsActive_turnsItOn() {
        let env = Environment(isAppActive: true)

        env.sut.hasFocus = true

        #expect(env.sut.isOn)
        #expect(env.switches.log == ["on"])
    }

    @Test
    func focusLost_turnsItOff() {
        let env = Environment(isAppActive: true)
        env.sut.hasFocus = true

        env.sut.hasFocus = false

        #expect(!env.sut.isOn)
        #expect(env.switches.log == ["on", "off"])
    }

    /// The field keeps its focus behind another app, but nothing typed there is Vault's.
    @Test
    func anotherAppInFront_turnsItOffThoughTheFieldKeepsFocus() {
        let env = Environment(isAppActive: true)
        env.sut.hasFocus = true

        env.app.isActive = false
        env.sut.appActivityDidChange()

        #expect(!env.sut.isOn)
        #expect(env.switches.log == ["on", "off"])
    }

    @Test
    func vaultBackInFront_withTheFieldStillFocused_turnsItOnAgain() {
        let env = Environment(isAppActive: true)
        env.sut.hasFocus = true
        env.app.isActive = false
        env.sut.appActivityDidChange()

        env.app.isActive = true
        env.sut.appActivityDidChange()

        #expect(env.sut.isOn)
        #expect(env.switches.log == ["on", "off", "on"])
    }

    @Test
    func focus_whileAnotherAppIsInFront_waitsForVault() {
        let env = Environment(isAppActive: false)

        env.sut.hasFocus = true

        #expect(!env.sut.isOn)
        #expect(env.switches.log.isEmpty)

        env.app.isActive = true
        env.sut.appActivityDidChange()

        #expect(env.sut.isOn)
        #expect(env.switches.log == ["on"])
    }

    /// Vault coming back to the front with no field focused leaves it off.
    @Test
    func vaultBackInFront_withNoFieldFocused_leavesItOff() {
        let env = Environment(isAppActive: false)

        env.app.isActive = true
        env.sut.appActivityDidChange()

        #expect(!env.sut.isOn)
        #expect(env.switches.log.isEmpty)
    }

    /// macOS counts each time it's turned on, so it's turned on and off exactly once each, however often it's told
    /// the same thing.
    @Test
    func repeatedChanges_turnItOnAndOffOnceEach() {
        let env = Environment(isAppActive: true)

        env.sut.hasFocus = true
        env.sut.hasFocus = true
        env.sut.appActivityDidChange()
        env.sut.hasFocus = false
        env.sut.hasFocus = false
        env.sut.appActivityDidChange()

        #expect(env.switches.log == ["on", "off"])
    }
}

extension VaultMacSecureInputTests {
    /// Whether Vault is the active app, as the test sets it.
    @MainActor
    final class AppActivity {
        var isActive: Bool

        init(isActive: Bool) {
            self.isActive = isActive
        }
    }

    /// Each time Secure Keyboard Entry was turned on or off, in order.
    @MainActor
    final class Switches {
        var log = [String]()
    }

    @MainActor
    struct Environment {
        let app: AppActivity
        let switches: Switches
        let sut: VaultMacSecureInput

        init(isAppActive: Bool) {
            let app = AppActivity(isActive: isAppActive)
            let switches = Switches()
            self.app = app
            self.switches = switches
            sut = VaultMacSecureInput(
                isAppActive: { app.isActive },
                turnOn: { switches.log.append("on") },
                turnOff: { switches.log.append("off") },
            )
        }
    }
}
