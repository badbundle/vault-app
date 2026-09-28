# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The app binary version was set to 1.0 throughout initial development and is considered unstable and not resilient.
Only app binary versions >2.0 should be used in production for this reason.

## [Unreleased]

### Added

- Initial release
- Minimum deployment target is iOS 17.4
- Storage for secure notes
- Storage for 2FA codes (TOTP, HOTP)
- Backup export
- Backup encryption
- App icon generated from a SwiftUI view (`VaultAppIcon`) with light, dark and tinted variants, via `make app-icon`
- Locked items show the vault door from the app icon, which spins open when the item is unlocked. Turning the lock on and saving locks the item on the spot, door shutting and wheel spinning, so the lock is seen to work
- Recovery phrases (crypto wallet seed words) as a new item type. They're always encrypted with a password and locked with the device passcode, shown as a numbered list, and checked against the wordlist and checksum of BIP39 (all 10 languages), SLIP-39, Electrum and Monero phrases, with any unrecognized words highlighted, plus an optional description that's encrypted along with the words. Even once unlocked, the words stay masked until tapped. They're hidden while the app is in the background or the screen is being recorded, and there's no way to copy them
- App Lock, in a new Security section of Settings and off by default: Vault stays behind Face ID, Touch ID or the passcode, starting locked and locking again in the background, straight away or after 1, 5 or 15 minutes (Require Unlock). The app switcher and Control Center only ever see a cover with the vault door
- An App Lock Password, set from App Lock in Settings, that encrypts the vault on this device and is asked for after Face ID or the passcode. It can't be reset, so the screen that sets it says so and shows when you last backed up. Wrong passwords wait longer each time, as iOS does, and the password can be changed or turned off. While it's on, widgets, QuickType and AutoFill show nothing from the vault
- A duress password, set from the App Lock Password screen, that opens a separate, empty vault instead of the real one, with its own backups. Vault can also erase every vault after 10 wrong App Lock Passwords in a row, if you turn that on. Delete All Data deletes every vault, whichever one it's done from. The FAQ explains duress passwords, and how to start a duress vault again without it
- Hide While Recording, on by default: a cover hides the whole app, and the AutoFill sheet, while the screen is recorded, mirrored or shared, and it works without App Lock
- New Items settings: whether new codes and notes start locked, and whether new codes start out offered in QuickType
- Tap a Code To, in a new Codes section of Settings: tapping a code copies it (as before) or opens its details. Either way, touch and hold a code for Copy Code and Show Details
- Show Next Code, off by default: in the last seconds of its countdown, a time-based code shows the next code, smaller, above its timer bar. Copying still takes the current code
- Show in Spotlight, in the Codes section of Settings and off by default: find a code by its site's name in Spotlight and Apple Intelligence, and open it in Vault. Only while App Lock is off, and never account names, locked or hidden codes. Turning on App Lock turns it off

### Fixed

- A scanned or imported code whose period or counter Vault can't work with is refused with an error, instead of being saved
- Backups containing an encrypted item (such as an encrypted note) couldn't be restored: the encryption IV's key didn't survive the backup's key encoding. The backup format is unchanged, so backups made before the fix restore too
- Removing a tag from an item didn't stick: the tag came back once the item was saved
- Restoring a backup turned QuickType back on for every code and reset every note's preview. Backups now keep both choices, and older backups restore as before
- A restore over the vault (Import & Override) that failed part way could leave the vault empty or half replaced. Now it leaves the vault untouched
- Deleted items, killphrases and search passphrases could linger in the vault's database files. Vault now scrubs them out after deleting or changing them, and again at launch, along with the database's own history of changes
- The Backups page could stop showing that a backup password was set when you came back to it
- Copying a PDF backup from its share sheet counted as saving it, and put the backup on the clipboard. Copy and Markup are gone from that share sheet, and backup PDFs no longer stay behind in temporary files
- The editor's Tags, Encryption and Password rows needed a second tap to open their sheets
- VoiceOver read the editor's text fields and recovery phrase words without their names
- Killphrases didn't delete anything, and items that only show for their passphrase couldn't be found, after restoring a backup on another iPhone or after an erase. Backups now carry the keys that check them, and restoring one adds them to this device. Backups made before this don't carry them, so their phrases only work on the device that made them
- Moving the vault to another device with QR codes counted as a backup, so the Backups page and the App Lock Password screen could show a recent backup when nothing had been saved. Transfers aren't counted any more, including one made before this change
- At the largest text sizes, codes in the feed ran off the edge of the screen, and the item editor wrapped its titles a word to a line with "Continue" split in two. The feed now shows a card per row at those sizes, and the editor puts each step's icon above its title
- Codes with a period other than 30 seconds, such as 60, came out wrong in AutoFill's QuickType bar and in widgets, which always worked them out as 30 second codes. They now use the code's own period, as the feed does

### Changed

- The keyboard no longer learns from anything typed into Vault: every text field, from note bodies and descriptions to passphrases, killphrases, searches and tag names, has autocorrection, predictive text and Writing Tools turned off, so none of it can turn up as a keyboard suggestion in another app. Fields written like sentences still capitalize them
- App icon refreshed: the same door and wheel, drawn flat in black on a white background (silver in the dark icon). A locked or encrypted item's door and the lock screen match
- The export page explains itself: a header says every export is the whole vault encrypted with your backup password, then the two options sit under "Keep a Backup" (a PDF to save or print) and "Move to Another Device" (QR codes for another device to scan, with no file saved), each saying what it makes and how to restore it
- Scanning a backup's QR codes says what to scan under the camera, then counts the codes as they come in. Each new code ticks off its tile with a light tap, and the last one plays the success haptic
- PDF backups and auto-backups are padded to a fixed size, at least 32 KB and then doubling, so a backup doesn't show how much its vault holds. A small vault's PDF backup has more QR codes as a result. Moving to another device isn't padded this way, so it stays quick
- A PDF backup's Password Hint starts empty, so nothing is printed on it in plain text unless you write a hint. It used to start with a sample description
- Decrypting an encrypted item plays its own take on the vault door: the wheel works a combination, turning one way, back the other and round to seat, then the door swings wide and the item opens. A wrong password floods the header red from the door, which rattles in its frame, and the error turns white as the red reaches it
- The feed's bottom bar minimizes while scrolling down, to a capsule showing the item count and active filter beside the search button (or the current search), and returns on scrolling up, at the top, or with a tap. It keeps its space while minimized, so the feed doesn't jump and still bounces at the bottom
- Search lives in the feed's bottom bar: the status bar sits bottom left and a search button bottom right, which opens the search field beneath the status bar. While searching, the status bar counts the matches alongside any tag filter
- The feed's bottom bar uses clear Liquid Glass with a scroll edge effect, and its tag filters and buttons have larger tap targets
- Everything copied from Vault follows the clipboard settings: text copied from notes and descriptions, text cut or copied while editing, a backup key's ID and codes copied from a widget are cleared after the Clear Clipboard time, and only reach other devices if Universal Clipboard allows it, which gains a Notes switch. The edit menu on notes and descriptions offers only Copy. Dragging a code out of the feed no longer drops it into another app, and still reorders the feed
- Text being edited offers only Cut, Copy, Paste, Select, Select All and Delete in its edit menu, without Share, Look Up, Translate or Search Web, and can't be dragged into another app. A recovery phrase's words can't be cut or copied while they're typed either
- Copied codes are cleared from the clipboard after 1 minute by default. Anyone who chose Never keeps it
- New codes are no longer offered in QuickType unless Show New Codes in QuickType is on
- QuickType no longer suggests locked codes
- Settings has a heading and short footer for every section, with icons colored by section, and Universal Clipboard opens its own sheet
- The App Lock Password shows the lock screen's vault door wherever it's set, changed or managed, so it's plainly the password the lock screen asks for. The backup password has a shield wherever it's set, entered or changed
- Decrypting a backup asks for its password under the backup password's shield, with the field ready to type in and Return to decrypt. While it works, it says it can take up to 3 minutes, and Cancel stops it. A wrong password shakes the field, and the right one opens the lock
- The Danger Zone is a sheet that says what deleting removes and what's kept, and asks you to confirm before it deletes anything. Deleting all data also deletes the backup password, so restoring an old backup afterwards needs its password
- Item pages look like the editor: the item's badge at the top and cards beneath it, with a larger live code on a code's page
- Tapping + opens one sheet that starts with choosing the kind of item and slides straight into its editor
- The Backups, Auto-Backup and Restore pages open with headers, and Backups leads with when you last backed up. Restore asks for Face ID or the passcode before it imports anything, even with no backup password set
- Auto-backup always keeps the newest backup it made, however long ago, so a shorter Keep Backups For time, or a vault that hasn't changed in a while, still leaves one
- Restore's import sheet opens with a header saying what's about to happen, with the symbol of the Restore row that opened it: importing, merging, or replacing the vault, in red. Choosing a PDF and scanning QR codes are rows beneath it. A file that isn't a backup says so in the header, with an error haptic, instead of in a red card
- Once the backup is decrypted, the import sheet's header says what importing will do, over a button named for it: Import, Merge, or Replace Vault in red. When it's done, a green tick bounces with the success haptic. If it fails, the header says why, with the button beneath to try again
- On a device with no passcode, Restore, the Backup Password sheet, the Danger Zone and deleting a set-aside vault say to set up a passcode, instead of asking to authenticate and failing
- When the vault can't be opened, its screen suggests restoring a backup of your iPhone or getting in touch, and says to keep Vault installed, since deleting the app deletes its data
- Auto-backup's cleanup only deletes backups it recorded making, instead of any auto-backup PDF in the folder. Existing setups are seeded once with the files the old cleanup would have deleted, so they carry on being cleaned up
- Choosing a shorter time in Keep Backups For asks first, and says that older auto-backups are deleted straight away
- The text in a code's timer bar is smaller and readable on every bar color
- Images in Markdown notes aren't loaded, so opening a note never goes online
- Widgets on the Lock Screen and in StandBy hide their codes, sites and accounts until the iPhone is unlocked, and copying a code from a widget asks for the iPhone to be unlocked first
- The Restore page offers Import & Merge and Import & Override only when the feed shows items. When it shows none, it offers Import Backup, which keeps anything already in the vault
- The AutoFill sheet locks when the iPhone does, as Vault does: with App Lock on, locking the iPhone with the sheet open hides the codes until the sheet is unlocked again
- Restoring a backup always asks for the password it was made with, even when it's the backup password set now. The backup password kept on the device only makes backups
- A new backup password has to be at least 8 characters, and not only numbers, like the App Lock Password. The form says so, and a password set before this keeps working
- The Backups FAQ explains that deleted items, including those a killphrase deleted, stay in backups made before they were deleted, and in an auto-backup folder until its older backups are cleaned up
- The wait after wrong App Lock Passwords keeps growing when a password opens Vault in between, and only gets shorter with time, by one wrong password for every hour that passes. A password that opens Vault still starts the count towards erasing after 10 again, and the erasing settings say so
- Setting a duress password asks for the current App Lock Password, which waits after wrong ones as changing the password does

### Removed

- The hand-made `VaultLogo.png` app icon (replaced by the generated set)
- The Universal Clipboard switches for passwords and other content, which had no effect
