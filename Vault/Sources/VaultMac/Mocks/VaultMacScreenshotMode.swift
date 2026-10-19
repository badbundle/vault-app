#if DEBUG
import AppKit
import FoundationExtensions
import ScreenCaptureKit
import SwiftUI
import VaultFeed

/// Launch-argument driven demo state for the Mac App Store screenshots, as `ScreenshotMode` is for iOS.
///
/// `make screenshots` (run from `Vault/`) launches a debug build with `-screenshot-scene <scene>`. The app then runs
/// on the demo vault (`DemoVault`), in memory, with settings, keychain items and storage of its own, so the Mac's own
/// vault, keychain and widgets are never read or written. Touch ID passes, the App Lock Password is a stand-in that's
/// set, and the app opens the scene in a window of a fixed size.
///
/// Every Vault window is kept out of screen captures (Hide While Recording), and capturing the screen would need a
/// permission of its own anyway, so the app captures the scene's window itself once it's settled: with
/// `-screenshot-fd <n>`, it writes the window as a PNG to that file descriptor, which `Screenshots/capture.sh` opens
/// for it, and quits. Its windows' `sharingType` lets it (`VaultMacWindowPrivacy`), in screenshot mode only. Compiled
/// out of release builds.
@MainActor
enum VaultMacScreenshotMode {
    /// A screen the app can be launched straight into for a screenshot.
    ///
    /// The raw values are the names `Screenshots/capture.sh` passes on the command line.
    enum Scene: String, CaseIterable {
        /// The list of items, with none open.
        case feed
        /// The first demo item's page, the "Cold storage" recovery phrase, opened with its password and Touch ID,
        /// with its words masked.
        case detail
        /// The first demo code's editor, part way through hiding it behind `DemoVault.hiddenItemsPassphrase`, locking
        /// it and giving it the killphrase `editorKillphrase`. Nothing is saved.
        case editor
        /// The lock screen, asking for the App Lock Password.
        case lock
        /// The Backups area, on the backup password's page.
        case backups
        /// The Settings window's Security tab, with the App Lock Password on.
        case settings
        /// The "Everyday wallet" recovery phrase's editor sheet: its words masked, and their checksum valid. Nothing is
        /// saved.
        case phraseEditor = "phrase-editor"
        /// The first demo code's page, with its code and countdown.
        case codeDetail = "code-detail"

        /// Whether the App Lock Password is entered, to show what's behind the lock screen.
        var entersAppLockPassword: Bool {
            self != .lock
        }

        /// The window the scene shows, which is the one captured.
        var windowID: String {
            self == .settings ? VaultMacScreenshotMode.settingsWindowID : VaultMacWindow.main.id
        }

        /// Whether the list in the window's middle column has a row selected, which only shows in the accent colour
        /// while the list has focus.
        var selectsInTheList: Bool {
            switch self {
            case .detail, .codeDetail, .backups: true
            case .feed, .editor, .lock, .settings, .phraseEditor: false
            }
        }
    }

    static let launchArgument = "-screenshot-scene"

    /// The scene named on the command line, or `nil` for a normal launch. A name that isn't a `Scene` is a bug in the
    /// capture script, so it fails loudly rather than showing the Mac's own vault.
    static let scene: Scene? = {
        guard let name = value(after: launchArgument) else { return nil }
        guard let scene = Scene(rawValue: name) else {
            let known = Scene.allCases.map(\.rawValue).joined(separator: ", ")
            fatalError("Unknown \(launchArgument) '\(name)'. Expected one of: \(known)")
        }
        guard UITestVaultStorage.current == nil else {
            fatalError("\(launchArgument) and \(UITestVaultStorage.launchArgument) can't be used together")
        }
        return scene
    }()

    static var isEnabled: Bool {
        scene != nil
    }

    /// `-screenshot-appearance light|dark`, light if it isn't given.
    static let appearance: NSAppearance.Name = {
        switch value(after: "-screenshot-appearance") {
        case nil, "light": .aqua
        case "dark": .darkAqua
        case let other?: fatalError("Unknown -screenshot-appearance '\(other)'. Expected one of: light, dark")
        }
    }()

    /// The file descriptor the drawn window is written to, from `-screenshot-fd`. Without one, the app stays open on
    /// the scene.
    static let outputDescriptor: Int32? = value(after: "-screenshot-fd").map { value in
        guard let descriptor = Int32(value), descriptor > 0 else {
            fatalError("Unknown -screenshot-fd '\(value)'. Expected a file descriptor, such as 1 for standard output")
        }
        return descriptor
    }

    /// The main window's size: 16:10, as the Mac App Store's screenshots are, and drawn at 2× it.
    static let mainWindowSize = CGSize(width: 1120, height: 700)

    /// Pixels to the point the window is captured at, which needs it on a Retina display.
    static let scale = 2.0

    /// How long a scene has to settle before its window is captured: the vault seeded, the lock opened and the page
    /// laid out.
    static let settleTime: Duration = .seconds(3)

    /// The App Lock Password the stand-in has, which the scenes behind the lock enter.
    static let appLockPassword = "correct horse battery"

    /// SwiftUI's identifier for the Settings window.
    nonisolated static let settingsWindowID = "com_apple_SwiftUI_Settings_window"

    /// The demo vault's last backup: 9:41 this morning, as in the iOS screenshots.
    static var lastBackupDate: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Stand-ins

    /// Touch ID always passes. `nil` for a normal launch.
    static var authenticationPolicy: (any DeviceAuthenticationPolicy)? {
        isEnabled ? VaultMacUITestAuthenticationPolicy(answers: [.allow]) : nil
    }

    /// The vault's storage directory, emptied at every launch, in place of the App Group's container.
    static let storageDirectory: URL = {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "screenshot-vault", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Unable to create the screenshot vault's directory: \(error)")
        }
        return directory
    }()

    /// Settings in a suite of their own, wiped on every launch, for both the app's defaults and the App Group's.
    static func makeDefaults() -> Defaults {
        Defaults(userDefaults: wipedDefaults(suiteName: "com.badbundle.vault.screenshots"))
    }

    /// The app lock's settings, likewise wiped, and only in defaults: on the Mac the real ones are in the keychain.
    static func makeAppLockSettingsStore() -> AppLockSettingsStore {
        let settings = AppLockSettingsStore(userDefaults: wipedDefaults(
            suiteName: "com.badbundle.vault.screenshots.app-lock",
        ))
        settings.isEnabled = true
        return settings
    }

    /// The App Lock Password: set, with erasing after failed passwords on.
    static func makeAppLockPasswordService() -> FakeAppLockPasswordService {
        FakeAppLockPasswordService(password: appLockPassword, erasesAfterFailedPasswords: true)
    }

    /// Keychain items in memory: the demo vault's killphrase and search passphrase keys.
    static let secureStorage = VaultMacScreenshotSecureStorage()

    /// The demo vault's backup password, set two weeks before its last backup.
    static let backupPasswordStore = DemoBackupPasswordStore(metadata: .init(
        lastSetDate: Calendar.current.date(byAdding: .day, value: -14, to: lastBackupDate),
    ))

    private static func wipedDefaults(suiteName: String) -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create the screenshot defaults suite '\(suiteName)'")
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private static func value(after argument: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        return arguments.dropFirst(index + 1).first ?? ""
    }

    // MARK: - The scene

    /// What the `editor` scene types in as a killphrase.
    static let editorKillphrase = "paper lantern"

    /// The editor the `editor` scene opens, once its item is known.
    private(set) static var editorRequest: VaultMacEditorRequest?

    /// Fills in the `editor` scene's editor: hidden behind `DemoVault.hiddenItemsPassphrase`, locked and given a
    /// killphrase, but not yet saved.
    static func showEditorScene(in viewModel: OTPCodeDetailViewModel) {
        guard scene == .editor else { return }
        viewModel.editingModel.detail.viewConfig = .requiresSearchPassphrase
        viewModel.editingModel.detail.searchPassphrase = DemoVault.hiddenItemsPassphrase
        viewModel.editingModel.detail.lockState = .lockedWithNativeSecurity
        viewModel.editingModel.detail.killphraseEnabled = true
        viewModel.editingModel.detail.newKillphrase = editorKillphrase
        scrollEditorToEnd()
    }

    /// Scrolls the editor's sheet to its end, where the killphrase is, with no field focused, and on from there just
    /// far enough that no row is cut off at the sheet's top edge. A form has no way to start scrolled to its end, and
    /// the sheet takes a moment to come up and lay out, so it keeps at it for a couple of seconds, well within
    /// `settleTime`.
    private static func scrollEditorToEnd() {
        Task {
            for _ in 0 ..< 5 {
                try? await Task.sleep(for: .milliseconds(400))
                for sheet in NSApp.windows where sheet.isSheet {
                    sheet.makeFirstResponder(nil)
                    if let scrollView = firstScrollingView(in: sheet.contentView) {
                        scrollToEndWithWholeRows(scrollView)
                    }
                }
            }
        }
    }

    /// Scrolls `scrollView`, whose document is flipped, to its end, then on past it, with room made below, until the
    /// top edge falls between two rows: halfway between the bottom of the field it would cut and the top of the next.
    private static func scrollToEndWithWholeRows(_ scrollView: NSScrollView) {
        guard let document = scrollView.documentView, document.isFlipped else { return }
        let clip = scrollView.contentView
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        let end = max(0, document.bounds.height - clip.bounds.height)
        // A row is a little taller than its field.
        let rowMargin = 8.0
        let fields = textFields(in: document)
            .map { $0.convert($0.bounds, to: document) }
            .sorted { $0.minY < $1.minY }
        var top = end
        if let cut = fields.first(where: { $0.minY - rowMargin < end && $0.maxY + rowMargin > end }),
           let next = fields.first(where: { $0.minY >= cut.maxY })
        {
            top = ((cut.maxY + next.minY) / 2).rounded()
        }
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: max(0, top - end), right: 0)
        clip.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(clip)
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(textFields(in:))
    }

    private static func firstScrollingView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? NSScrollView, let document = scrollView.documentView,
           document.bounds.height > scrollView.contentView.bounds.height
        {
            return scrollView
        }
        return view.subviews.lazy.compactMap(firstScrollingView(in:)).first
    }

    /// Opens an encrypted demo item's page with its password, as someone would, in a scene that shows one. Every
    /// encrypted demo item has the same password (`DemoVault.encryptedItemPassword`).
    static func openEncryptedItem(_ viewModel: EncryptedItemDetailViewModel) async {
        guard isEnabled, case .base = viewModel.state else { return }
        viewModel.enteredEncryptionPassword = DemoVault.encryptedItemPassword
        await viewModel.startDecryption()
    }

    /// The Backups page the `backups` scene opens.
    static var backupsPage: VaultMacBackupsPage? {
        scene == .backups ? .password : nil
    }

    /// Seeds the demo vault, opens the scene, and once it's settled, writes its window to `outputDescriptor` and
    /// quits. Called once, as the main window first appears.
    static func run(openSettings: OpenSettingsAction) async {
        guard let scene else { return }
        log("opening the \(scene.rawValue) scene")
        // The app's, so every window and sheet takes it, whatever the Mac's own appearance.
        NSApp.appearance = NSAppearance(named: appearance)
        // While it's still locked: resizing lays the window out again there and then, which mustn't be the first time
        // a code's row is drawn.
        window(VaultMacWindow.main.id)?.setContentSize(mainWindowSize)
        let seeded: DemoVault.SeededItems
        do {
            seeded = try await DemoVault.seed(
                store: VaultMacRoot.vaultStore,
                dataModel: VaultMacRoot.vaultDataModel,
                backupEventLogger: VaultMacRoot.backupEventLogger,
                backupDate: lastBackupDate,
            )
        } catch {
            fatalError("Unable to seed the screenshot vault: \(error)")
        }

        // What's open behind the lock, before it opens, so the main window starts on it.
        let firstItem = seeded.firstItem.decryptedItem
        switch scene {
        case .detail:
            VaultMacRoot.feedModel.selectedItemID = firstItem.id
        case .codeDetail:
            VaultMacRoot.feedModel.selectedItemID = seeded.firstCodeID
        case .editor:
            VaultMacRoot.feedModel.selectedItemID = seeded.firstCodeID
            if let item = VaultMacRoot.vaultDataModel.items.first(where: { $0.id == seeded.firstCodeID }),
               case let .otpCode(code) = item.item
            {
                editorRequest = .editCode(code, item.metadata)
            }
        case .phraseEditor:
            let phrase = seeded.everydayWallet
            VaultMacRoot.feedModel.selectedItemID = phrase.decryptedItem.id
            // As its page's Edit opens it, once its password and Touch ID have opened the page.
            if case let .recoveryPhrase(words) = phrase.decryptedItem.item {
                editorRequest = .editRecoveryPhrase(words, phrase.decryptedItem.metadata, phrase.encryptionKey)
            }
        case .backups:
            VaultMacRoot.feedModel.sidebarSelection = .backups
        case .feed, .lock, .settings:
            break
        }

        log("seeded the demo vault")
        let appLock = VaultMacRoot.appLockService
        await appLock.unlock()
        if scene.entersAppLockPassword {
            await appLock.unlock(password: appLockPassword)
        }
        log("unlocked as far as the scene goes")
        if scene == .settings {
            openSettings()
            try? await Task.sleep(for: .milliseconds(500))
            guard await showSecuritySettings() else {
                log("couldn't open the Settings window's Security tab; nothing captured")
                exit(1)
            }
        }
        try? await Task.sleep(for: settleTime)
        guard let outputDescriptor else { return }
        guard let window = window(scene.windowID) else {
            fatalError("The \(scene.rawValue) scene's window isn't open")
        }
        guard await bringToFront(window, focusingTheList: scene.selectsInTheList) else {
            log("couldn't bring the window to the front, so it would be drawn inactive; nothing captured")
            exit(1)
        }
        log("capturing")
        do {
            let png = try await pngData(of: window)
            FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: false).write(png)
        } catch {
            log("couldn't capture the \(scene.rawValue) scene's window: \(error)")
            exit(1)
        }
        // An open sheet would hold up quitting.
        NotificationCenter.default.post(name: closeSheets, object: nil)
        try? await Task.sleep(for: .milliseconds(500))
        NSApp.terminate(nil)
    }

    /// Brings the app and `window` to the front, so the window is drawn active, with coloured buttons, and with
    /// `focusingTheList`, the middle column's list focused, so its selection is in the accent colour. That holds even
    /// though something else, such as the terminal running `capture.sh`, is in front: `NSApp.activate()` only asks,
    /// and is turned down then. Its predecessor still takes the front, but it's deprecated, which the build treats as
    /// an error, so it's called by name. Someone using the Mac can take the front back meanwhile, so it tries a few
    /// times. `false` if it never got there.
    private static func bringToFront(_ window: NSWindow, focusingTheList: Bool) async -> Bool {
        typealias Activate = @convention(c) (AnyObject, Selector, Bool) -> Void
        let selector = NSSelectorFromString("activateIgnoringOtherApps:")
        let activate = unsafeBitCast(NSApp.method(for: selector), to: Activate.self)
        func isReady() -> Bool {
            NSApp.isActive && isKey(window) && (!focusingTheList || window.firstResponder is NSTableView)
        }
        for _ in 0 ..< 10 {
            if isReady() {
                // Long enough for the window to draw itself active.
                try? await Task.sleep(for: .milliseconds(500))
                if isReady() {
                    return true
                }
            }
            activate(NSApp, selector, true)
            (window.attachedSheet ?? window).makeKeyAndOrderFront(nil)
            if focusingTheList, let list = middleColumnList(in: window) {
                window.makeFirstResponder(list)
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return false
    }

    /// The list in the window's middle column: the leftmost one that isn't the sidebar's.
    private static func middleColumnList(in window: NSWindow) -> NSTableView? {
        func lists(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(lists(in:))
        }
        guard let contentView = window.contentView else { return nil }
        let sidebarEdge = 120.0
        return lists(in: contentView)
            .map { ($0, $0.convert($0.bounds, to: nil).minX) }
            .filter { $0.1 > sidebarEdge }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Posted once the window's captured: the main window closes its sheet.
    static let closeSheets = Notification.Name("VaultMacScreenshotMode.closeSheets")

    /// Chooses the Settings window's Security tab, as a click on it in the window's toolbar does, so the app's own
    /// tab view stays as it is: unbound, so the window opens on the tab it showed last. `false` if it isn't there.
    private static func showSecuritySettings() async -> Bool {
        guard let toolbar = window(settingsWindowID)?.toolbar,
              let security = toolbar.items.first(where: { $0.label == "Security" }),
              let action = security.action
        else { return false }
        NSApp.sendAction(action, to: security.target, from: security)
        // The tab changes once SwiftUI next updates.
        try? await Task.sleep(for: .milliseconds(500))
        return toolbar.selectedItemIdentifier == security.itemIdentifier
    }

    /// Whether `window`, or the sheet in front of it, is the key window.
    private static func isKey(_ window: NSWindow) -> Bool {
        window.isKeyWindow || window.attachedSheet?.isKeyWindow == true
    }

    /// What the scene is doing, on standard error, which `capture.sh` shows if a capture fails.
    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("screenshot mode: \(message)\n".utf8))
    }

    private static func window(_ id: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true && $0.isVisible }
    }

    /// The whole window, title bar, toolbar and any sheet included, without its shadow, as macOS draws it.
    ///
    /// ScreenCaptureKit hands an app its own windows without asking for the screen recording permission, once their
    /// sharing type lets it. Drawing the window in the app instead (`cacheDisplay`) leaves out everything on Liquid
    /// Glass or drawn with vibrancy, such as the sidebar. macOS draws a window at its display's scale, so it has to be
    /// on a Retina display to come out at `scale`.
    static func pngData(of window: NSWindow) async throws -> Data {
        guard window.backingScaleFactor >= scale else {
            throw CaptureError.notRetina(window.backingScaleFactor)
        }
        let content = try await SCShareableContent.currentProcess
        guard let captured = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw CaptureError.windowNotShareable
        }
        let filter = SCContentFilter(desktopIndependentWindow: captured)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CaptureError.notEncodable
        }
        return png
    }

    enum CaptureError: Error, CustomStringConvertible {
        /// The window's on a display that isn't Retina, so it would come out at less than `scale`.
        case notRetina(CGFloat)
        /// ScreenCaptureKit doesn't offer the window: it isn't on screen, or its sharing type keeps it out.
        case windowNotShareable
        case notEncodable

        var description: String {
            switch self {
            case let .notRetina(windowScale):
                "the window is on a display at \(windowScale)x; the screenshots need a Retina display, at 2x"
            case .windowNotShareable:
                "ScreenCaptureKit doesn't offer the window"
            case .notEncodable:
                "the capture couldn't be encoded as a PNG"
            }
        }
    }
}

/// `SecureStorage` in memory, for the screenshots' demo vault.
actor VaultMacScreenshotSecureStorage: SecureStorage {
    private var items = [String: Data]()

    func store(data: Data, forKey key: String) {
        items[key] = data
    }

    func retrieve(key: String) -> Data? {
        items[key]
    }

    func storeSilent(data: Data, forKey key: String) {
        items[key] = data
    }

    func retrieveSilent(key: String) -> Data? {
        items[key]
    }

    func attributes(key: String) -> SecureStorageAttributes? {
        items[key].map { _ in SecureStorageAttributes(modificationDate: nil) }
    }

    func remove(key: String) {
        items[key] = nil
    }
}

/// The widgets' keychain items in memory, for the screenshots' demo vault.
final class VaultMacScreenshotWidgetKeychain: WidgetKeychainStoring {
    private let data = SharedMutex<Data?>(nil)

    func read() throws -> Data? {
        data.value
    }

    func save(_ data: Data) throws {
        self.data.modify { $0 = data }
    }

    func remove() throws {
        data.modify { $0 = nil }
    }
}
#endif
