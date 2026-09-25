# Vault

A secret storage manager (2FA codes, secret notes) with built-in encrypted backup.
It can create encrypted backups to a portable PDF document that you can print (as a hard copy) or save anywhere to restore from later.

It has advanced security features which promote plausible deniability (killcodes and hidden items) and can be used as an ultimate offline backup for storing all your secret data.
There is purposely no automatic or online backup, so you never need to worry about where your data might be going.

## How to use Vault

There's a few ways that you can use Vault to store your data:

1. Super secret data
   - Store data you really don't want to be accessed in encrypted notes, like cryptocurrency private keys. Hide them and add a killcode so, if under duress, you can wipe them with plausible deniability. Restore from a backup when you get home.

2. Store OTP codes
   - 2FA OTP codes provide a second layer of security for accessing your online accounts and are strongly recommended to setup whereever possible. Vault can store these codes natively and can replace other apps like Google Authenticator. Google Authenticator, in particular, has a far from ideal backup solution (automatic sync to Google's servers) or a manual QR code-based transfer. Neither match the security guarantees of Vault.

## Tenets

- [x] **Platform native**: it should look like Apple made this app.
- [x] **Modern**: we should use modern features and push for fast deprecations.
- [x] **Open source**: no binary dependencies or obfuscated stuff.
- [x] **Robust**: test-driven development, modular PRs/commits.
- [x] **Duress-resistant**: see [`MANIFESTO.md`](./MANIFESTO.md) for the security principles that govern what Vault will and will not do.

## Features

- [x] OTP codes
- [x] Notes
- [x] Markdown notes
- [x] Encrypted notes
- [x] Item tags
- [x] Instant item search
- [x] Paper backups
- [x] Fully offline, no servers at all
- [x] Plausible deniability of item existance with killcodes and hidden items

### Development Tenets

- [x] **Tested**: high level of test coverage, mockolo for mocking, Swift Testing, snapshot tests
- [x] **Safe**: Swift 6 concurrency
- [x] **Modern**: iOS 26, SwiftUI, Structured Concurrency
- [x] **Availability**: iPhone & iPad Support
- [x] **Modular**: Swift Package w/ multiple targets
- [x] **Resilient**: everything should be versioned, we never need to break old clients, old backups should always be able to be restored

## Contributing

Development takes place in `/Vault`, so take a look in there.
As soon as we are able, we will be dropping the xcodeproj project wrapper and going all-in on the Swift Package Manager.

- `Vault.xcworkspace` what you should open
- `/Vault` Swift Package that defines targets used by the app, build settings, tooling.
- `/VaultApp` minimal wrapper that packages this into an executable application.

### Validation

There is no hosted CI. Changes are validated on the developer's Mac, and the result is posted to the commit on GitHub as the **Validate (local)** status check. `main` requires that check, so a PR can't be merged until its latest commit has passed.

1. Once per clone, enable the pre-push hook: `git config core.hooksPath .githooks`
2. Commit your changes, then run `make validate` from `/Vault`.

`make validate` ([`scripts/validate.sh`](./scripts/validate.sh)) checks out the exact commit into a separate worktree, so uncommitted changes and your usual DerivedData can't affect the result. It then runs, with Xcode 27.0:

- `make lint`
- the Fastlane config check (skipped, and noted on the check, if the Ruby version in `.ruby-version` isn't installed)
- a build and full run of the `iOSAllTests` test plan on a throwaway iPhone 18 Pro Max / iOS 27.0 simulator, created for the run and deleted afterwards

If the commit is already on GitHub, the result is posted straight away. Otherwise it's stored, and the pre-push hook posts it when you push, so you can validate before or after pushing. Every new commit needs validating again. Logs are kept in `.git/validate/logs/`.

The check is self-attested: it records that the commit passed on the machine that posted it, rather than on independent CI.
