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

### Fixed

- N/A

### Changed

- App icon refreshed: the same door and wheel, now layered with a metal gradient, rim light and shadow

### Removed

- The hand-made `VaultLogo.png` app icon (replaced by the generated set)
