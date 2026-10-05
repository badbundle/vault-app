# The Mac app

The design of record for Vault on the Mac (VAULT-101), written for VAULT-102 before any code. Each sub-issue builds
part of it, and updates this file if what it finds changes the design. It was researched in October 2026, against
Xcode 27 and the macOS 27 SDK, for an app that runs on macOS 26 and later, as the Swift package already declares.

[`MANIFESTO.md`](../MANIFESTO.md) binds the Mac app exactly as it binds the iOS one, and
[`docs/security-model.md`](./security-model.md) gains the Mac's promises as they're built (see
[The security model](#the-security-model)).

## Contents

1. [Decisions](#decisions)
2. [What the Mac app is](#what-the-mac-app-is)
3. [Each iOS protection on the Mac](#each-ios-protection-on-the-mac)
4. [Packaging](#packaging)
5. [Modules](#modules)
6. [Validation](#validation)
7. [The security model](#the-security-model)
8. [Sub-issues](#sub-issues)

## Decisions

Bradley's, on VAULT-101 (2026-09-29):

1. **The Mac app requires an App Lock Password.** There's no unencrypted vault on the Mac. Setting the password is
   part of the first launch, it can't be skipped, and it can't be turned off. So the vault on the Mac is only ever
   the encrypted vault file (G33), and never depends on FileVault alone.
2. **No CLI, and no other way into the vault from outside the app.** The vault's data stays in the app. Only the app
   and its AutoFill extension can open it. There are no XPC services, no URL schemes or App Intents that read items,
   no AppleScript, no Services, no Shortcuts actions, no Spotlight or Quick Look extensions, and no files outside the
   App Group's container.

Following from those, and from the manifesto:

3. **Its own vault, with no sync** (G69). Items move between the Mac and other devices only as they do between
   iPhones: a backup restored, or the QR transfer, scanned with the Mac's camera or Continuity Camera.
4. **A native SwiftUI macOS app**, not Mac Catalyst and not the iPad app on Apple silicon. It has its own UI module,
   `VaultMac`, on the same shared modules as the iOS app.
5. **The same App Store record and bundle ID** (`com.badbundle.vault`), with macOS added to it, for Universal
   Purchase. It's free, like the iOS app, with no in-app purchases.

Mine, for Bradley to review:

6. **It looks like Apple's Passwords app on the Mac.** The README's first tenet is that Vault should look like Apple
   made it, and Passwords is Apple's own app for codes and secrets. So the main window has three columns: a sidebar,
   a list of items with their live codes, and the selected item's page. Settings is the standard Settings window
   (⌘,), and About is the standard About window, from the Vault menu. That changes VAULT-105's sidebar, which listed
   Settings and About as sidebar entries.
7. **A team-prefixed App Group, which is also the only keychain access group.** The Mac app and its AutoFill
   extension share `442P244AFS.com.badbundle.vault`, rather than the iOS app's `group.com.badbundle.vault-group`.
   On the Mac, an App Group that starts with the team ID needs no provisioning profile, and it's a keychain access
   group for the data protection keychain too. So the app needs no restricted entitlement, and a development build
   signed with the Apple Development certificate runs as it is, which `make validate` relies on. See
   [Keychain](#keychain).
8. **Secure Keyboard Entry while a Vault field has focus.** On the Mac, other apps can watch the keyboard, if the user
   has allowed them to (Input Monitoring), and that includes the search field, where killphrases and search
   passphrases are typed. So Vault turns on secure event input whenever one of its text fields has focus, as
   Terminal's Secure Keyboard Entry does, and not only in password fields.
9. **No widgets, recommended.** With the App Lock Password always on, iOS's widgets only ever show Vault as locked
   (G44), so a Mac widget would only ever say "Locked". VAULT-115 decides, after the first release.

## What the Mac app is

### The main window

One main window, as Passwords has. Opening another isn't offered (no ⌘N for windows: ⌘N adds an item).

- **Sidebar:** Items (all of them), then each tag, then Backups. A tag's row filters the list, as the tag filter does
  on iOS.
- **The list:** each item's row shows its name, and for a code, its live code with its timer. Show Next Code works as
  on iOS. Clicking a code copies it, or opens its page, as Tap a Code To says.
- **The item's page:** the selected item, with the same content as on iOS. Editing opens a sheet, with the same steps
  as the iOS editor.
- **The toolbar:** the search field, and + for a new item. Search works exactly as on iOS: hidden items only appear
  while the whole search is their passphrase (G8), and a killphrase deletes its item at once, without saying so (G1,
  G2).
- **Backups:** the same page as on iOS, in the window's content area: the backup password, Keep a Backup, Move to
  Another Device, Auto-Backup and Restore.

While Vault is locked, every window shows only the lock screen. Sheets are closed, and the Settings window shows that
Vault is locked, with a button that brings the main window forward to unlock it.

### Menus and shortcuts

The standard menus, with Vault's commands in them:

| Command | Shortcut | Menu |
| --- | --- | --- |
| New Item | ⌘N | File |
| Find | ⌘F | Edit (focuses the search field) |
| Copy Code | ⌘C | Edit (with an item selected and no text selected) |
| Edit Item | ⌘E | Item |
| Delete Item | ⌘⌫ | Item (asks first) |
| Lock Vault | ⌃⌘L | Vault |
| Settings… | ⌘, | Vault |
| About Vault | | Vault |
| Vault Help | ⌘? | Help (opens the FAQ) |

There's no Undo for anything that changes the vault (C6). The Edit menu's Undo and Redo are only for text being typed.

## Each iOS protection on the Mac

### App Lock and the App Lock Password

- **The first launch** asks for an App Lock Password before anything else, with the same rules (G27) and the same
  warning that it can't be reset (G30). There's nothing to skip to, and Settings has no Turn Off Password.
- **Unlocking** is LocalAuthentication first, with `deviceOwnerAuthentication`: Touch ID, an Apple Watch, or the
  Mac's login password. Then the App Lock Password, through the shared `AppLockService`, `VaultUnlockService` and
  `AppLockPasswordUnlocker`, with the same deadline (G11), counter and waits (G19, G26). A Mac with no login password
  is like an iPhone with no passcode: Vault says to set one, and never gets as far as the App Lock Password (G25).
- **Duress passwords and erasing after 10** are the shared code, and work exactly as on iOS (G10–G21, G76).
- **There's no plain store on the Mac.** iOS sets the password by converting its SQLite store into the encrypted vault
  (`VaultEncryptionConverter`). The Mac's first launch converts an empty in-memory store the same way, so it reuses the
  converter's verified, crash-safe commit, and no SQLite store is ever written to disk. After an erase, the Mac goes
  back to its first launch, and the fresh store the erase leaves is in memory too.
- **Key derivation** is calibrated on the Mac that sets the password, as on iOS (G64): 64 MiB, 3–32 passes, about half
  a second. On an M5 Max, that's about 24 passes.

### Locking

The Mac locks the vault, dropping its items, caches, search and keys (G29):

- **at once, whatever the Require Unlock delay,** when the screen locks (`com.apple.screenIsLocked`), the screen saver
  starts, the displays sleep, the Mac sleeps (`NSWorkspace.willSleepNotification`), or the user switches to another
  account (`NSWorkspace.sessionDidResignActiveNotification`). These are the Mac's equivalents of iOS's
  `protectedDataWillBecomeUnavailable`;
- **when Vault stops being the active app,** straight away or after the Require Unlock delay (G22). The default is
  Immediately, as on iOS. Hiding Vault (⌘H) or closing its window counts as leaving it;
- **from the Vault menu,** with Lock Vault (⌃⌘L);
- **when it quits.** Every launch starts locked, as on iOS.

iOS shows a privacy cover while the app is inactive, for the app switcher. The Mac has no app switcher snapshot, and a
window left on screen behind another app is what the Require Unlock delay chose to keep. So the Mac has no privacy
cover: with the delay at Immediately, leaving Vault locks it.

### Hide While Recording

iOS can only notice the screen being captured, and cover the app (G24). On the Mac, a window whose `sharingType` is
`.none` can't be read by other processes, so it's left out of screenshots, screen recordings, screen sharing and
AirPlay. Hide While Recording, on by default (C7), sets it on every Vault window, including the Settings and About
windows, sheets and alerts. That's stronger than iOS: nothing captures Vault's windows at all, rather than a cover
going up once capture is noticed.

It depends on macOS honouring `sharingType`, which `RELEASE.md`'s Mac checks test by hand on each macOS version.
Turning the setting off sets `.readOnly`, the system's default.

### Other ways a window's contents could leak

- **Mission Control, App Exposé and the Dock's previews:** once locked, every window shows only the lock screen.
- **State restoration:** off for every window (`restorationBehavior(.disabled)`, and `isRestorable = false`), so
  macOS never saves a window's contents to disk.
- **Window titles** are only ever "Vault" (and "Settings" for the Settings window), never an item's name, so the
  Window menu, Mission Control's labels and accessibility tools show nothing else.
- **No Handoff** (`NSUserActivity`), **no Share menu** for items, and **no Quick Look** or other extensions.
- **The Services menu** gets nothing from Vault's fields: they offer no Services.
- **Accessibility:** apps the user has allowed to control the Mac (Privacy & Security → Accessibility) can read the
  text of any window, Vault's included. That's an accepted limit, as a screen reader needs it.

### The clipboard

The same rules as iOS (G50), with AppKit's equivalents:

- Everything Vault copies is marked with `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType`, so
  clipboard managers neither show nor keep it.
- It's kept to this Mac with `NSPasteboard.prepareForNewContents(with: .currentHostOnly)`, unless Universal Clipboard
  is allowed for that kind of text, which it isn't by default (C7).
- It's cleared after the Clear Clipboard time, 1 minute by default. AppKit has no expiry date, so Vault clears it
  itself, and only if the pasteboard's `changeCount` shows it still holds what Vault put there.
- Recovery phrases can't be copied (G41), and a drag out of the list gives only the item's ID (G51).

Whether macOS 26's own clipboard history, in Spotlight, keeps concealed and transient items is checked by hand
(`RELEASE.md`), and becomes an accepted limit if it does.

### The keyboard and text

Every text field turns off what could learn from it or send it elsewhere (G52):

- autocorrection, spelling and grammar checking, text completion and inline predictions;
- Writing Tools (`writingToolsBehavior(.disabled)`);
- the Services menu.

As on iOS, every field declares this, through a Mac `SecretTextInput`, and a declaration test fails for any field
that doesn't. SwiftUI's `TextField` doesn't expose every one of these on the Mac, so fields that need them are thin
`NSTextField` and `NSTextView` wrappers.

Decision 8: Secure Keyboard Entry (`EnableSecureEventInput`) is on while any Vault field has focus, and off again as
soon as none has.

The Edit menu offers only the plain text actions, and copies made from a field go through Vault's clipboard (G51).

### Keychain

Vault already uses the data protection keychain (`kSecUseDataProtectionKeychain`) everywhere, which is what macOS
needs for the iOS keychain's behaviour: no prompts, no access lists, and items that never sync
(`kSecAttrSynchronizable` false).

On the Mac, the data protection keychain needs the app to have a keychain access group. `keychain-access-groups` is a
restricted entitlement on the Mac, needing a provisioning profile, but an App Group that starts with the team ID isn't,
and it also serves as a keychain access group. So (decision 7) the Mac's only keychain access group is its App Group,
`442P244AFS.com.badbundle.vault`, shared by the app and its AutoFill extension and nothing else. Every keychain item
the Mac writes names that group explicitly, so a development build and an App Store build, whose default groups
differ, keep their items in the same place.

The difference from iOS: there, the backup password and the killphrase and search passphrase keyrings are in the app's
own group, which the AutoFill extension can't read. On the Mac, the extension could read them. It doesn't, and it's
the same team's code, but it's listed under the accepted limits.

### Spotlight

Always off. On iOS, Show in Spotlight only works while App Lock is off (G49), and the Mac's password is always on. The
Mac's Settings don't offer it, and the Mac app never touches Core Spotlight.

### QuickType and AutoFill

- **Suggestions:** macOS's credential identity store is what lists codes in Safari's suggestions, as QuickType does on
  iOS. With the password always on, it's kept empty and never written (G46).
- **AutoFill:** since macOS 15, a credential provider extension can fill one-time codes, with `ProvidesOneTimeCodes`
  in its `ASCredentialProviderExtensionCapabilities` and `prepareOneTimeCodeCredentialList(for:)`. The macOS 27 SDK
  has the same API as iOS 18 and later. VAULT-112 builds it, under the iOS AutoFill rules: the App Lock Password asked
  for in its own sheet after Touch ID or the Mac's password (G25, G48); its attempts counted with the app's, never the
  tenth (G20); locking when the Mac locks (G29); and never a locked or hidden code (G47). VAULT-112 checks the API
  works as its headers say, and records what it finds here.

### Widgets

See decision 9. If VAULT-115 builds them, they follow every iOS widget rule (G44, G45).

### Backups, restore and transfer

All of it is the shared code, so every backup and transfer rule holds as it does on iOS (G54–G62, G77–G79).

- **Keep a Backup** saves the encrypted PDF through `NSSavePanel`, straight to where the user chooses, or prints it
  with `NSPrintOperation`. There's no temporary file and no share sheet, so G43 and G53 don't apply.
- **Move to Another Device** shows the transfer's QR codes, for an iPhone or iPad to scan.
- **Auto-Backup** writes to a folder the user picks with `NSOpenPanel`, such as one in iCloud Drive. Vault keeps access
  to it across launches with an app-scoped, security-scoped bookmark (`.withSecurityScope`), as iOS keeps its folder.
- **Restore** reads a PDF the user picks, or scans a device's transfer codes with the Mac's camera or Continuity
  Camera (`AVCaptureMetadataOutput`, on macOS since 13). It always asks for the backup's own password (G59), after
  Touch ID or the Mac's password (G31).
- **Adding a code** can also read a QR code from an image file the user picks, with Vision's barcode detection.

## Packaging

### Targets

In `VaultApp/VaultApp.xcodeproj`, beside the iOS targets, which don't change:

| Target | Kind | Bundle ID |
| --- | --- | --- |
| `VaultMacApp` | macOS app, SwiftUI `App` lifecycle | `com.badbundle.vault` |
| `VaultMacAutofill` | credential provider extension (VAULT-112) | `com.badbundle.vault.VaultAutofill` |
| `VaultMacAppUITests` | macOS UI tests | `com.badbundle.vault.MacUITests` |

The Mac app's `@main` is as thin as the iOS app's: one scene from `VaultMac`. It's built for Apple silicon and Intel,
with a deployment target of macOS 26. Its version and build numbers follow the iOS app's, and `RELEASE.md`'s global
rule for build numbers (VAULT-114).

### App Sandbox

The App Store needs the sandbox, and it's what keeps other apps out of Vault's container. The Mac app has only these
entitlements:

| Entitlement | Why |
| --- | --- |
| `com.apple.security.app-sandbox` | Required. |
| `com.apple.security.application-groups`: `442P244AFS.com.badbundle.vault` | The vault file and the settings the AutoFill extension shares, and the keychain access group. |
| `com.apple.security.files.user-selected.read-write` | Saving a backup, choosing the auto-backup folder, and restoring or reading an image. |
| `com.apple.security.files.bookmarks.app-scope` | Keeping the auto-backup folder across launches. VAULT-110 checks whether macOS 26 still needs it. |
| `com.apple.security.device.camera` | Scanning QR codes, with `NSCameraUsageDescription`. |
| `com.apple.security.print` | Printing a backup. |

It never has:

- **network entitlements** (`network.client`, `network.server`): Vault makes no network requests (G70), and without
  them, the sandbox makes sure it can't;
- `keychain-access-groups` or iCloud entitlements (decision 7, G69);
- temporary exceptions, file access beyond user-selected files (downloads, pictures and so on), Apple Events or
  scripting targets, or Mach lookup exceptions;
- the hardened runtime's exceptions: no JIT, unsigned memory, DYLD environment variables, or disabled library
  validation;
- `com.apple.security.get-task-allow` in release builds, so no other process can attach to Vault.

The hardened runtime is on, so other code can't be injected into Vault's process.

The AutoFill extension gets the sandbox, the App Group and the AutoFill entitlement
(`com.apple.developer.authentication-services.autofill-credential-provider`), and nothing else. The app itself doesn't
need the AutoFill entitlement: it never writes the credential identity store, which stays empty on the Mac.

A test (VAULT-105) reads the built app's entitlements and fails on any not in the first table.

### Info.plist

No `CFBundleURLTypes`, `NSServices`, `NSAppleScriptEnabled`, `NSUserActivityTypes` or document types.
`ITSAppUsesNonExemptEncryption` is `NO`, as on iOS: all encryption is CryptoKit, on the Mac too
([`docs/export-compliance.md`](./export-compliance.md)). `LSApplicationCategoryType` is Utilities.

### Where the vault lives

In the App Group's container, `~/Library/Group Containers/442P244AFS.com.badbundle.vault/`, through
`VaultSharedStorage`, as on iOS. That holds the vault file, its storage state and the defaults the AutoFill extension
shares. Settings only the app reads stay in its own container, under `~/Library/Containers/com.badbundle.vault/`.

On a Mac with Apple silicon, file protection works as it does on iOS (found in VAULT-103): the vault file is written
with complete protection, as on iOS, so it can't be read or written while the screen is locked. The Mac app locks at
once when the screen locks anyway (see [Locking](#locking)). It also means the Mac's tests can't write such files while
`make validate` runs with the screen locked, so the macOS test plan has debug builds write their files with
`completeUntilFirstUserAuthentication` instead (`VAULT_TEST_FILE_PROTECTION`).

The sandbox keeps other sandboxed apps out of both. Since macOS 14, other apps reading another app's container ask the
user first, and since macOS 15 that covers Group Containers too. A process running as the user with Full Disk Access
can still copy the vault file. It's encrypted, so, as with a copy of an iPhone's files, they can only guess at the
password offline (G33, G64).

### Signing

- **Development and `make validate`:** signed with the Apple Development certificate of team `442P244AFS`, manual
  style, with no provisioning profile. That works because none of the entitlements above is restricted (decision 7).
  The AutoFill extension's entitlement is restricted, so it needs a development profile. VAULT-112 works out how
  `make validate` builds and tests it without one.
- **The App Store:** a Mac App Store provisioning profile for each target, made with the release lanes (VAULT-114).

## Modules

| Module | iOS | macOS | Notes |
| --- | --- | --- | --- |
| CryptoEngine, CArgon2, FoundationExtensions, VaultCore, VaultKeygen, VaultSettings | yes | yes | Already build for macOS. |
| ImageTools, VaultExport | yes | yes | Their rendering moves off UIKit (VAULT-104). |
| VaultBackup, VaultFeed | yes | yes | Build for macOS once ImageTools and VaultExport do (VAULT-103). |
| VaultAppIcon | yes | yes | SwiftUI only. The Mac's app icon is rendered from it, like iOS's. |
| VaultiOS, VaultiOSShared, VaultiOSAutofill, VaultiOSWidgets | yes | no | Unchanged. |
| `VaultMac` | no | yes | The Mac app's views, its composition root and the AppKit pieces. |
| `VaultMacAutofill` | no | yes | The credential provider's views (VAULT-112). |

`VaultMac` doesn't reuse VaultiOS's views: they're iOS views, full of UIKit and iOS-only modifiers, and making them
build for both would change the iOS app. It reuses everything beneath them. The shared view models, the App Lock, the
stores, backups and import, the OTP timers and copy actions are all in VaultFeed already.

What changes in the shared modules:

- **`VaultSharedStorage.appGroupID`** is the Mac's App Group on macOS (decision 7).
- **The keychain items with an explicit access group** (the attempt counter, the device wrap stamp and the device key)
  use it, and so does the Mac's `SecureStorage` (decision 7).
- **`VaultBackgroundTime`** has a Mac version: Mac apps aren't suspended, so it only stops macOS ending Vault abruptly
  (`ProcessInfo.disableSuddenTermination()`) until an unlock, a conversion or a rekey has finished.
- **`DeviceTransferExportViewModel`**, VaultFeed's one UIKit file, keeps its QR codes as images both platforms can
  draw.
- **`VaultEraser`** can leave its fresh store in memory, for the Mac.

`VaultMac` has its own composition root, `VaultMacRoot`, which wires the shared services as `VaultRoot` does on iOS,
without what the Mac doesn't have: the plain SQLite store, widgets, QuickType and Spotlight. Its tests are
`VaultMacTests`.

### PDF backups and images

ImageTools draws QR codes with Core Image, then wraps them in a `UIImage`. VaultExport lays out and draws the PDF
backup with `UIGraphicsPDFRenderer`, `UIFont` and `UIColor`. VAULT-104:

- puts Core Graphics and Core Text, which both platforms have, under one renderer for both, if iOS's snapshot tests pass
  unchanged with it. If they don't, the UIKit renderer stays on iOS, and the Mac gets one with Core Graphics;
- keeps the PDF exactly as it is: the same QR payloads, page layout, plain-text header and hint (G58), so a backup
  made on either platform restores on the other;
- uses a small platform image type, `UIImage` or `NSImage`, wherever a rendered image is handed out.

## Validation

`make validate` keeps every iOS check, and adds, in order:

1. **Build (macOS):** `CI_macOS` with its `macOS_SupportedTests` plan, for `platform=macOS`. The plan grows from
   today's five test targets to every shared module's tests, and then `VaultMacTests`.
2. **Tests (macOS).**
3. **Build Mac app UI tests**, then **Mac app UI tests**: `VaultMacAppUITests`, which launch the app on an in-memory
   test vault, as the iOS UI tests do (`UITestVault`), so they never touch the Mac's own vault.

Tests that can only run on iOS, such as those of iOS's own APIs, are marked as such with a trait, not deleted. Tests
that need the data protection keychain only run where the test process has a keychain access group.

**Mac snapshot tests** are pinned to a configuration, as iOS's are to the iPhone 18 Pro Max: a fixed window size, a
backing scale factor of 2, an explicit light or dark appearance, and macOS 27. They fail with a message, rather than
recording, on anything else.

A run takes several minutes longer. As now, never run two vault-app validations at once.

## The security model

Each sub-issue adds the rows for what it builds to [`docs/security-model.md`](./security-model.md), taking the next
free G numbers, so that the file always matches what's built. It gains:

- **"Who it protects against"** covers the Mac: someone who picks up your unlocked Mac, and someone with a copy of
  Vault's files from a Mac.
- **A new "The Mac app" section**, with the Mac's own promises:
  - the password is always on: set at first launch, can't be skipped or turned off, and the vault is only ever the
    encrypted file (VAULT-106);
  - the lock triggers in [Locking](#locking) (VAULT-106);
  - `sharingType` on every window, titles that are only "Vault", no state restoration, and nothing shown while locked
    (VAULT-109);
  - the Mac's clipboard (VAULT-107);
  - the Mac's text fields, and Secure Keyboard Entry (VAULT-108);
  - the sandbox and the entitlements, and no way in from outside the app (VAULT-105, VAULT-113);
  - Spotlight and the identity store always empty (VAULT-106, VAULT-112);
  - AutoFill (VAULT-112).
- **Rows that hold unchanged on the Mac** because they're kept by shared code (duress, the vault file, cryptography,
  backups) say nothing new, and the section says so.
- **Rows that don't apply on the Mac**, listed in the section with the reason:
  - G23: there's no app switcher cover (see [Locking](#locking)).
  - G28 and G16: turning the password off, which the Mac doesn't offer.
  - G38 and G39: the plain SQLite store.
  - G43 and G53: the PDF's temporary file and share sheet.
  - G44 and G45: widgets, unless VAULT-115 builds them.
  - G49: Spotlight, which is always off.
- **Rows with a Mac version:** G22 (leaving the app, rather than the background), G24 (`sharingType`, rather than a
  cover), G25 and G31 (Touch ID, an Apple Watch or the Mac's password; a Mac with no login password), G29 (the
  Mac's lock triggers), G41 (masking while Vault isn't active), G50 (the Mac's clipboard), G51 and G52 (the Mac's
  text fields).
- **New accepted limits:**
  - Something running as you with Full Disk Access can copy the vault file, and guess at the password offline.
  - Apps you've allowed to control the Mac (Accessibility) can read what Vault's windows show, and what's typed into
    its fields, while they show it. Secure Keyboard Entry only keeps keystrokes from apps watching the keyboard.
  - Hiding windows from capture depends on macOS honouring `sharingType`.
  - The AutoFill extension can read every Vault keychain item (decision 7).
  - A Mac that's compromised, or someone with an administrator's access to it, is out of scope, as a jailbroken iPhone
    is.

## Sub-issues

The sub-issues on VAULT-101 stand, in the same order, with these changes:

- **VAULT-103** also makes ImageTools and VaultExport build for macOS, since VaultBackup and VaultFeed depend on them.
  Until VAULT-104, their UIKit drawing stays iOS-only, behind `canImport(UIKit)`, and so do the tests that draw.
- **VAULT-105:** the sidebar is Items, tags and Backups, with Settings and About as windows (decision 6). The App
  Group is team-prefixed (decision 7). The hardened runtime is on, and a test checks the entitlements.
- **VAULT-106:** the first launch converts an in-memory store (see
  [App Lock and the App Lock Password](#app-lock-and-the-app-lock-password)). Lock Vault is in the Vault menu.
- **VAULT-107:** the three-column window (decision 6).
- **VAULT-108:** Secure Keyboard Entry (decision 8), and the Mac's `SecretTextInput`.
- **VAULT-109** to **VAULT-113** stand as they are.
- **VAULT-114** (Bradley's) gains the Mac's clipboard history and `sharingType` checks for `RELEASE.md`.
- **VAULT-115** (Bradley's): decision 9 recommends closing it.
