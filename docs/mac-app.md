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
7. **A team-prefixed App Group, and keychain access groups as on iOS.** The Mac app and its AutoFill extension
   share `442P244AFS.com.badbundle.vault`, rather than the iOS app's `group.com.badbundle.vault-group`: on the Mac, an
   App Group that starts with the team ID needs nothing registered for it. The keychain is as on iOS: the app's own
   group (`keychain-access-groups`, `…vault.private`), and the App Group for the few items the extension reads too.
   See [Keychain](#keychain).

   This was first planned without `keychain-access-groups`, so that development builds needed no provisioning
   profile. VAULT-106 found the Mac refuses the data protection keychain (`errSecMissingEntitlement`) to an app with
   no profile, whatever its App Group. So development builds, and `make validate`, sign with a Mac development profile
   (see [Signing](#signing)).
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
- **The item's page:** the selected item, with the same content as on iOS. Edit opens the item's editor in a sheet
  (see [Adding and editing items](#adding-and-editing-items)).
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
| New Code | ⌘N | File |
| New Note | ⇧⌘N | File |
| New Recovery Phrase | | File |
| Find | ⌘F | Edit (focuses the search field) |
| Copy Code | ⌘C | Edit (with an item selected and no text selected) |
| Edit Item | ⌘E | Item (while the item's page shows it) |
| Delete Item | ⌘⌫ | Item (asks first; while text has focus, ⌘⌫ deletes text as usual) |
| Lock Vault | ⌃⌘L | Vault |
| Settings… | ⌘, | Vault |
| About Vault | | Vault |
| Vault Help | ⌘? | Help (opens the Help window) |

There's no Undo for anything that changes the vault (C6). The Edit menu's Undo and Redo are only for text being typed.

### Settings, Help and About

The Settings window (⌘,) has two tabs, with every setting that means something on the Mac, at iOS's defaults (C7):

- **General:** Tap a Code To, Show Next Code, the Clear Clipboard time, Universal Clipboard for codes and for notes
  (both off), and Lock New Items.
- **Security:** Require Unlock, Hide While Recording, the App Lock Password (Change Password, Set Duress Password and
  Erase Vault After 10 Failed Passwords, each with the current password, in a sheet), and the Danger Zone's Delete All
  Data, which asks first and then for Touch ID or the Mac's password (G15).

Not on the Mac: Turn Off Password (G85), App Lock itself, which the password keeps on, Show in Spotlight, which is
always off with the password on (G49), and Show New Codes in QuickType, as there's no QuickType to fill (see
[QuickType and AutoFill](#quicktype-and-autofill)).

The Help window (⌘?) has the iOS app's FAQ pages, worded for either device, then the terms of use, the privacy
policy, the libraries Vault uses and where its source is. The About window has the version, links to those pages,
and the other Bad Bundle apps (`BadBundleApps`). Neither shows anything from the vault, so neither waits for it to be
unlocked.

### Adding and editing items

New Code, New Note and New Recovery Phrase, in the File menu and behind the toolbar's +, open the editor in a sheet,
as Edit does for the open item. Each editor is one form, rather than iOS's steps, with the same fields and checks, on
the same shared view models (`OTPCodeDetailViewModel`, `SecureNoteDetailViewModel` and
`RecoveryPhraseDetailViewModel`) and `VaultDataModelEditorAdapter`:

- **A code's key** is typed in, scanned with the Mac's camera or Continuity Camera (`AVCaptureSession`, only while the
  scanner is open, with nothing kept), or read from an image the user chooses (Vision). Whichever it is, it's checked
  as on iOS before it fills the form (G77).
- **A note** can have a password of its own. It counts once it's typed the same twice, and is never stored (G42).
  Once a note or recovery phrase is saved, its page asks for the password again.
- **A recovery phrase** is checked against its standard's word list and checksum as it's typed, each word in a secure
  field, and always has a password of its own (G41).
- **Privacy & Security** is per item only, as on iOS (C1, C8, C9): lock, visibility with a search passphrase, and a
  killphrase.
- **Deleting** asks first, from the editor or Delete Item, and can't be undone (C6).

Locking Vault closes the sheet, and what was typed into it is dropped.

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
- **when another app comes to the front,** straight away or once the Require Unlock delay has passed with Vault still
  behind (G22). The default is Immediately, as on iOS. Hiding Vault (⌘H) counts as leaving it. Coming back to the
  front starts unlocking by itself, as the iOS app does coming back to the foreground;
- **from the Vault menu,** with Lock Vault (⌃⌘L);
- **when a window is minimised,** so the Dock's image of it shows only the lock screen (`VaultMacWindowPrivacy`);
- **when it quits,** which closing its window does, as for a single-window Mac app. Every launch starts locked, as on
  iOS.

`VaultMacLockTriggers` listens for all of them.

iOS shows a privacy cover while the app is inactive, for the app switcher. The Mac has no app switcher snapshot, and a
window left on screen behind another app is what the Require Unlock delay chose to keep. So the Mac has no privacy
cover: with the delay at Immediately, leaving Vault locks it.

Locked items lock as on iOS (G32): a locked item's page shows nothing of it until Touch ID or the Mac's password
passes, and asks again whenever it's opened. A recovery phrase always asks, whatever its stored lock state, once its
own password has opened it, and again once Vault stops being the active app (G41).

### Hide While Recording

iOS can only notice the screen being captured, and cover the app (G24). On the Mac, a window whose `sharingType` is
`.none` can't be read by other processes, so it's left out of screenshots, screen recordings, screen sharing and
AirPlay. Hide While Recording, on by default (C7), sets it on every Vault window, including the Settings and About
windows, sheets and alerts. That's stronger than iOS: nothing captures Vault's windows at all, rather than a cover
going up once capture is noticed.

It depends on macOS honouring `sharingType`, which `RELEASE.md`'s Mac checks test by hand on each macOS version.
Turning the setting off sets `.readOnly`, the system's default.

`VaultMacWindowPrivacy` sets it on every window of Vault's as it opens, and again each time one updates, so a sheet or
alert has it as soon as it appears, and a change to the setting reaches every window at once. Panels macOS shows for
Vault, such as the Open panel, are drawn by macOS, not Vault, and show only files.

### Other ways a window's contents could leak

- **Mission Control, App Exposé and the Dock's previews:** once locked, every window shows only the lock screen.
  Minimising a window locks Vault first, so the Dock's image of it shows only that.
- **State restoration:** off for every window (`restorationBehavior(.disabled)`, and `isRestorable = false`), so
  macOS never saves a window's contents to disk. No window can be a tab, either.
- **Window titles** are only ever "Vault", "About Vault", "Vault Help" and the Settings window's tab, never an item's
  name, so the
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
  itself, and only if the pasteboard's `changeCount` shows it still holds what Vault put there. Quitting Vault, which
  ends that timer, clears it at once.
- Every copy goes through `VaultMacPasteboard`: clicking a code in the list (or opening its page, as Tap a Code To
  says), Copy Code on its page, and Copy (⌘C) while no text has focus. The Edit menu's Copy goes to the text that has
  focus otherwise.
- An item's page shows its text without letting it be selected, so nothing on it is copied around Vault's clipboard:
  a note has Copy Note instead.
- A locked code asks for Touch ID or the Mac's password before it's copied (G32).
- Recovery phrases can't be copied (G41), and a drag out of the list gives only the item's ID (G51).

Whether macOS 26's own clipboard history, in Spotlight, keeps concealed and transient items is checked by hand
(`RELEASE.md`), and becomes an accepted limit if it does.

### The keyboard and text

Every text field turns off what could learn from it or send it elsewhere (G52, G89):

- autocorrection, spelling and grammar checking, text completion, inline predictions and every substitution;
- Writing Tools;
- the Services menu.

SwiftUI's `TextField`, `TextEditor` and `searchable` edit with AppKit's shared field editor, which turns some of these
on and doesn't let Vault turn them all off. So every field the user types into, other than a secure field, edits with
`VaultMacFieldEditor`, an `NSTextView` with all of them off: `VaultMacTextField` and `VaultMacSearchField` (thin
`NSTextField` and `NSSearchField` wrappers that hand their cells that field editor) and `VaultMacTextEditor`, for a
note. `VaultMacTextInputDeclarationTests` fails for any of SwiftUI's own in the Mac app's sources.

Secure fields, for passwords, passphrases, killphrases and a recovery phrase's words, are SwiftUI's, which AppKit
already keeps from learning or copying. As on iOS, each declares `secretTextInput()`, the Mac's counterpart, and
`SecretTextInputDeclarationTests` fails for any that doesn't.

Decision 8: Secure Keyboard Entry (`EnableSecureEventInput`) is on while a `VaultMacFieldEditor` has focus, and off
again as soon as it loses focus or leaves its window. A secure field turns it on itself.

A field's menu offers only Cut, Copy, Paste and Select All, Cut and Copy go through Vault's clipboard as details that
never leave this Mac (G51, G87), and text can't be dragged out of a field.

### Keychain

Vault already uses the data protection keychain (`kSecUseDataProtectionKeychain`) everywhere, which is what macOS
needs for the iOS keychain's behaviour: no prompts, no access lists, and items that never sync
(`kSecAttrSynchronizable` false).

On the Mac, the data protection keychain only answers an app whose provisioning profile grants it a keychain access
group: without one, every call fails with `errSecMissingEntitlement`, App Group or not (found in VAULT-106). So the Mac
app has `keychain-access-groups`, and its App Group is a keychain access group too:

- the backup password and the killphrase and search passphrase keyrings are in the app's own group,
  `442P244AFS.com.badbundle.vault.private` (`SecureStorage` with the default group, the first in its
  `keychain-access-groups`), which the AutoFill extension can't read;
- the attempt counter, the device key and the wrap stamp name the App Group, `442P244AFS.com.badbundle.vault`, which
  the extension shares, and which is its only keychain access group.

The app's own group isn't named for the app, as the iOS app's is, because on the Mac that name is the App Group's, and
the extension would read it too (found in VAULT-112).

### Spotlight

Always off. On iOS, Show in Spotlight only works while App Lock is off (G49), and the Mac's password is always on. The
Mac's Settings don't offer it, and the Mac app never touches Core Spotlight.

### QuickType and AutoFill

- **Suggestions:** macOS's credential identity store is what lists codes in Safari's suggestions, as QuickType does on
  iOS. With the password always on, it's kept empty and never written (G46).
- **AutoFill:** since macOS 15, a credential provider extension can fill one-time codes, with `ProvidesOneTimeCodes`
  in its `ASCredentialProviderExtensionCapabilities` and `prepareOneTimeCodeCredentialList(for:)`. VAULT-112 checked
  the macOS 27 SDK: `ASOneTimeCodeCredential`, `ASOneTimeCodeCredentialRequest`,
  `prepareOneTimeCodeCredentialList(for:)` and `completeOneTimeCodeRequest(using:)` are all there, available from macOS
  15, as on iOS 18. So the Mac has an AutoFill extension, `VaultMacAutofill`, under the iOS AutoFill rules (G95):
  - its sheet asks for Touch ID or the Mac's password, then the App Lock Password, with its own app lock, which starts
    locked (G25, G48);
  - its attempts are counted with the app's (`AutofillVaultService`), and it never makes the last one before the
    vault would be erased: that one is only ever made at the app's lock screen (G20);
  - it locks the vault again when the Mac locks, sleeps or its screen saver starts (`VaultMacLockTriggers`' lists),
    and at the end of every request (G29);
  - it never offers a locked or hidden code, and its search never checks killphrases: their keys are never loaded in
    the extension (G2, G47);
  - Hide While Recording keeps its sheet out of every capture, as it does the app's windows (G24, G91).

  With the identity store empty, nothing is filled without the sheet: `provideCredentialWithoutUserInteraction(for:)`
  always asks for it. Until Vault's first launch has set the App Lock Password, the sheet says to open Vault. The
  extension never touches `VaultMacRoot`, which recovers and converts the vault at the app's launch: it only reads
  the vault as the app left it, from the App Group. Show New Codes in QuickType isn't offered on the Mac, as there's
  no QuickType for it to fill.

  Whether Safari offers Vault's codes as its headers say is checked by hand (`RELEASE.md`, "Checking a build on a
  Mac").

### Widgets

See decision 9. If VAULT-115 builds them, they follow every iOS widget rule (G44, G45).

### Backups, restore and transfer

All of it is the shared code, so every backup and transfer rule holds as it does on iOS (G54–G62, G77–G79, G93). The
sidebar's Backups lists the pages in the window's middle column, with when this Mac last backed up, and the open page
is in the detail column.

- **Backup Password:** whether it's set, and setting or changing it in a sheet, after Touch ID or the Mac's password,
  with the App Lock Password's rules (G27). Each vault has its own (G17).
- **Keep a Backup** saves the encrypted PDF through `NSSavePanel`, straight to where the user chooses, named as on
  iOS, or prints it with `NSPrintOperation`. There's no temporary file and no share sheet, so G43 and G53 don't apply.
  It's logged as a backup once it's saved or printed, as a completed share is on iOS.
- **Move to Another Device** shows the transfer's QR codes, for an iPhone or iPad to scan, two seconds each. Closing
  the page, or locking, stops them and forgets the encrypted vault they carried (`DeviceTransferExportViewModel.stop()`).
- **Auto-Backup** writes to a folder the user picks with `NSOpenPanel`, such as one in iCloud Drive, whenever the vault
  changes. Vault keeps access to it across launches with a security-scoped bookmark (`.withSecurityScope`, made and
  read so on macOS by `iCloudDriveProvider`), as iOS keeps its folder. If the folder moves and the bookmark goes
  stale, the user chooses it again.
- **Restore** reads a PDF the user picks, or scans a device's transfer codes with the Mac's camera or Continuity
  Camera (`AVCaptureMetadataOutput`), until it has every one. It always asks for the backup's own password (G59),
  after Touch ID or the Mac's password (G31), and asks again once the page closes or Vault stops being the active
  app. An empty vault imports; otherwise Merge or Replace, as on iOS.
- **Adding a code** can also read a QR code from an image file the user picks, with Vision's barcode detection.

## Packaging

### Targets

In `VaultApp/VaultApp.xcodeproj`, beside the iOS targets, which don't change:

| Target | Kind | Bundle ID |
| --- | --- | --- |
| `VaultMacApp` | macOS app, SwiftUI `App` lifecycle, built as `Vault.app` | `com.badbundle.vault` |
| `VaultMacAutofill` | credential provider extension (VAULT-112) | `com.badbundle.vault.VaultAutofill` |
| `VaultMacAppTests` | tests that run inside the launched app | `com.badbundle.vault.MacAppTests` |
| `VaultMacAppUITests` | macOS UI tests | `com.badbundle.vault.MacUITests` |

The Mac app's `@main` is as thin as the iOS app's: one scene from `VaultMac`, `VaultMacScene`, which has the main
window, the About window and Settings. Its icon is `VaultMacAppIconView`, the iOS icon's artwork on the Mac's icon
grid, which `make app-icon` renders into `VaultMacApp`'s asset catalog at every size. It's built for Apple silicon and Intel,
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
| `keychain-access-groups`: `442P244AFS.com.badbundle.vault.private`, then `442P244AFS.com.badbundle.vault` | The app's own keychain items, which the AutoFill extension can't read, then the App Group's. |

The provisioning profile adds two more, which name the app and its team: `com.apple.application-identifier` and
`com.apple.developer.team-identifier`.

It never has:

- **network entitlements** (`network.client`, `network.server`): Vault makes no network requests (G70), and without
  them, the sandbox makes sure it can't;
- a keychain access group but its own and the App Group's, or iCloud entitlements (G69);
- temporary exceptions, file access beyond user-selected files (downloads, pictures and so on), Apple Events or
  scripting targets, or Mach lookup exceptions;
- the hardened runtime's exceptions: no JIT, unsigned memory, DYLD environment variables, or disabled library
  validation;
- `com.apple.security.get-task-allow` in release builds, so no other process can attach to Vault.

The hardened runtime is on, so other code can't be injected into Vault's process.

The AutoFill extension gets the sandbox, the hardened runtime, the App Group, the App Group as its only keychain
access group, and the AutoFill entitlement
(`com.apple.developer.authentication-services.autofill-credential-provider`), and nothing else. The app itself doesn't
need the AutoFill entitlement: it never writes the credential identity store, which stays empty on the Mac.

`make validate`'s "Mac app entitlements" check builds the app as it runs (a build for testing has entitlements of
Xcode's own), and fails unless the app and its extension are each signed with the hardened runtime, sandboxed in the
App Group, with only their own keychain access groups, and with no entitlement outside their lists and the profile's
two, apart from a development build's `get-task-allow`.

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

- **Development and `make validate`:** manual style, with the Apple Development certificate of team `442P244AFS` and
  the "Vault Mac Development" profile, made in the developer account for `com.badbundle.vault` on 5 October 2026, with
  the Mac Studio that validates registered on it. It lasts a year (until 5 October 2027). Another Mac that builds Vault
  has to be added to it, and the profile downloaded again. The tests that run inside the app and the UI test runner
  are signed with the certificate alone.
- **The AutoFill extension:** the same, with the "Vault Mac AutoFill Development" profile, made for
  `com.badbundle.vault.VaultAutofill` on 5 October 2026 (until 5 October 2027), with the same Mac registered.
- **The App Store:** a Mac App Store provisioning profile for each target, made with the release lanes (VAULT-114).

## Modules

| Module | iOS | macOS | Notes |
| --- | --- | --- | --- |
| CryptoEngine, CArgon2, FoundationExtensions, VaultCore, VaultKeygen, VaultSettings | yes | yes | Already build for macOS. |
| ImageTools, VaultExport | yes | yes | Their rendering moves off UIKit (VAULT-104). |
| VaultBackup, VaultFeed | yes | yes | Build for macOS once ImageTools and VaultExport do (VAULT-103). |
| VaultAppIcon | yes | yes | SwiftUI only. The Mac's app icon is rendered from it, like iOS's. |
| VaultiOS, VaultiOSShared, VaultiOSAutofill, VaultiOSWidgets | yes | no | Unchanged. |
| `VaultMac` | no | yes | The Mac app's views, its composition root and the AppKit pieces, and the AutoFill extension's (in `Autofill/`, with a root of its own), which its target subclasses, as the iOS extension's does. |

`VaultMac` doesn't reuse VaultiOS's views: they're iOS views, full of UIKit and iOS-only modifiers, and making them
build for both would change the iOS app. It reuses everything beneath them. The shared view models, the App Lock, the
stores, backups and import, the OTP timers and copy actions are all in VaultFeed already.

What changes in the shared modules:

- **`VaultSharedStorage.appGroupID`** is the Mac's App Group on macOS (decision 7), which the keychain items with an
  explicit access group (the attempt counter, the device wrap stamp and the device key) name.
- **`VaultStorageRecovery`** knows the Mac's plain store is only in memory: a first launch stopped mid-conversion
  leaves only the encrypted files it began, which the journal shows can go.
- **`VaultEraser`** leaves the Mac a fresh store in memory, and `AppLockService.lockNow()` locks at once, for Lock
  Vault and the end of the Require Unlock delay.
- **`VaultBackgroundTime`** has a Mac version: Mac apps aren't suspended, so it only stops macOS ending Vault abruptly
  (`ProcessInfo.disableSuddenTermination()`) until an unlock, a conversion or a rekey has finished.
- **`DeviceTransferExportViewModel`**, VaultFeed's one UIKit file, keeps its QR codes as images both platforms can
  draw.

`VaultMac` has its own composition root, `VaultMacRoot`, which wires the shared services as `VaultRoot` does on iOS,
without what the Mac doesn't have: the plain SQLite store, widgets, QuickType and Spotlight. Its tests are
`VaultMacTests`.

### PDF backups and images

ImageTools draws QR codes with Core Image, and VaultExport lays out and draws the PDF backup. On iOS they use UIKit:
`UIImage`, `UIGraphicsPDFRenderer`, `UIFont` and `UIColor`. What VAULT-103 and VAULT-104 did:

- **The types are platform aliases**, `PlatformImage`, `PlatformFont`, `PlatformColor`, `PlatformEdgeInsets`,
  `PlatformPDFRenderer` and `PlatformPDFRendererContext`, which are the UIKit types on iOS. So iOS draws exactly as it
  did, and its tests pass unchanged.
- **The Mac draws with `CoreGraphicsPDFRenderer`**, which does what `UIGraphicsPDFRenderer` does with a Core Graphics
  PDF context: each page in UIKit's coordinates, origin at the top left, with AppKit's text and image drawing going
  into it. The same layout code draws both platforms' pages.
- **QR codes are the same images on both:** Core Image draws them, and the Mac resizes them with Core Graphics at three
  times their size in points, as the iPhone does, with no smoothing. In a backup, each is a 214-pixel square image on
  either platform.
- **The PDF is the same format:** the same QR payloads, page layout, plain-text header and hint (G58). The Mac's text
  has slightly taller lines, so its QR codes start a few points lower down the page, and nothing a restore reads
  differs. The backup corpus has a Mac-made PDF that every iOS test run restores, and every PDF in it restores from
  its QR codes alone, read one by one, as scanning the paper does.

## Validation

`make validate` keeps every iOS check, and adds, in order:

1. **Build (macOS):** `CI_macOS` with its `macOS_SupportedTests` plan, for `platform=macOS`. The plan grows from
   today's five test targets to every shared module's tests, and then `VaultMacTests`.
2. **Tests (macOS).**
3. **Build Mac app tests**, **Mac app tests** and **Mac app entitlements**: the app, launched with `VaultMacAppTests`
   inside it, then the entitlements check above.
4. **Build Mac UI tests**, then **Mac UI tests**: `VaultMacAppUITests`. From VAULT-106 they launch the app on a test
   vault, as the iOS UI tests do (`UITestVault`), so they never touch the Mac's own vault. They run unattended, and
   with the screen locked: `xcodebuild` sets up their automation session itself.

Tests that can only run on iOS, such as those of iOS's own APIs, are marked as such with a trait, not deleted. Tests
that need the data protection keychain only run where the test process has a keychain access group.

**Mac snapshot tests** are pinned to a configuration, as iOS's are to the iPhone 18 Pro Max: a fixed window size, an
explicit light or dark appearance, en_US in UTC, and macOS 27, which `assertSnapshot` checks before it compares
anything. `.macWindow(width:height:appearance:)` draws a SwiftUI view in a window whose backing scale is always 2:
with the screen locked, as it often is while `make validate` runs, a window would otherwise draw text at 1x. The
Mac's text antialiasing still varies a little from run to run, so views are compared perceptually (98%), not pixel for
pixel. The Mac's images are kept in a `macOS` folder beside each test file's iOS ones.

They draw the same whether the screen is locked or not, as validation often runs on a locked Mac: a locked screen
leaves the screen's scale at 1 and changes its colours. So a window is drawn in a window of its own whose scale is
always 2, a PDF at a scale of 3 into sRGB and written out as exactly those pixels, and the coloured test images in a
PDF are sRGB bitmaps rather than drawn as the screen draws them. Each pixel's colours only have to be close, so the
small shifts in colour that are left don't fail them, but every pixel of a PDF has to match, and all but 1% of a
window's. (SnapshotTesting's perceptual precision would do the same, but it throws inside Core Image on macOS 27 as
soon as two images differ.)

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
- **VAULT-108:** Secure Keyboard Entry (decision 8), the Mac's field editor and `secretTextInput()`, and an Item menu
  for Edit Item and Delete Item.
- **VAULT-109:** minimising a window locks Vault, and no window can be a tab.
- **VAULT-110:** the Backups pages are in the middle and detail columns, and transfers can be stopped.
- **VAULT-111:** Settings has General and Security tabs, and Help is a window of its own.
- **VAULT-112:** the AutoFill extension, and the app's own keychain group renamed so the extension can't read it.
- **VAULT-113** stands as it is.
- **VAULT-114** (Bradley's) gains the Mac's clipboard history and `sharingType` checks for `RELEASE.md`.
- **VAULT-115** (Bradley's): decision 9 recommends closing it.
