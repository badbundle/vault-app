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

### Fixed

- Backups containing an encrypted item (such as an encrypted note) couldn't be restored: the encryption IV's key didn't survive the backup's key encoding. The backup format is unchanged, so backups made before the fix restore too

### Changed

- App icon refreshed: the same door and wheel, now layered with a metal gradient and rim light on a vibrant aqua-to-blue background, with no shadow behind the wheel. In the dark icon the door itself takes on the aqua and blue, so a locked item's door is blue in dark mode too
- The export page explains itself: a header says every export is the whole vault encrypted with your backup password, then the two options sit under "Keep a Backup" (a PDF to save or print) and "Move to Another Device" (QR codes for another device to scan, with no file saved), each saying what it makes and how to restore it
- Decrypting an encrypted item plays its own take on the vault door: the wheel works a combination, turning one way, back the other and round to seat, then the door swings wide and the item opens. A wrong password floods the header red from the door, which rattles in its frame, with the error in white
- The feed's bottom bar minimizes while scrolling down, to a capsule showing the item count and active filter beside the search button (or the current search), and returns on scrolling up, at the top, or with a tap. It keeps its space while minimized, so the feed doesn't jump and still bounces at the bottom
- Search lives in the feed's bottom bar: the status bar sits bottom left and a search button bottom right, which opens the search field beneath the status bar. While searching, the status bar counts the matches alongside any tag filter
- The feed's bottom bar uses clear Liquid Glass with a scroll edge effect, and its tag filters and buttons have larger tap targets

### Removed

- The hand-made `VaultLogo.png` app icon (replaced by the generated set)
