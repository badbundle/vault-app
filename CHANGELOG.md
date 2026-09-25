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

- App icon refreshed: the same door and wheel, now layered with a metal gradient, rim light and shadow
- The feed's bottom bar minimizes to a single capsule showing the item count and active filter while scrolling down, and returns on scrolling up, at the top, or with a tap
- The feed's bottom bar uses clear Liquid Glass with a scroll edge effect, and its tag filters and buttons have larger tap targets

### Removed

- The hand-made `VaultLogo.png` app icon (replaced by the generated set)
