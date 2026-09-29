# Vault

Vault is an open-source iPhone and iPad app for the secrets you can't afford to lose: two-factor codes, private notes and crypto recovery phrases. It's fully offline, with no servers, no accounts, no sync, no analytics and no network requests. And it's built for the moment someone forces you to unlock it.

[badbundle.com/apps/vault](https://badbundle.com/apps/vault)

## Who it's for

- Anyone who wants their 2FA codes and secrets on their own device, backed up where they choose, rather than synced to someone else's servers.
- Anyone who might be made to unlock their iPhone, at a border, in a robbery or at home. Face ID and the passcode don't stop that, so Vault has an App Lock Password, a duress password, hidden items and killphrases. [`MANIFESTO.md`](./MANIFESTO.md) sets out the threat model.

## Features

### 2FA codes

- Time-based (TOTP) and counter-based (HOTP) codes, added by scanning a QR code or typing in the secret.
- Tap a code to copy it, or to open its details. Copies are cleared after 1 minute by default, and stay on the device unless you allow Universal Clipboard.
- AutoFill for one-time codes, QuickType suggestions for the codes you choose, and widgets on the Home Screen, the Lock Screen and in StandBy.
- Show Next Code near the end of a code's countdown, and Show in Spotlight, which is off by default and works only while App Lock is off.

### Notes and recovery phrases

- Notes in plain text or Markdown, with tags and instant search. Images in notes are never loaded.
- Lock any item behind Face ID, Touch ID or the passcode, and encrypt a note with a password of its own.
- Recovery phrases (crypto wallet seed words), always encrypted and locked. They're checked against the BIP39 (all 10 languages), SLIP-39, Electrum and Monero word lists and checksums, masked until tapped, and can't be copied.

### When you're forced to unlock it

- App Lock, off by default: Face ID, Touch ID or the passcode, locking straight away or after 1, 5 or 15 minutes, with a cover in the app switcher.
- An App Lock Password that encrypts the whole vault on the device with AES-256-GCM. It's asked for after Face ID or the passcode, and wrong ones wait longer each time, as iOS does.
- A duress password that opens a separate vault, with its own backups, instead of the real one.
- Hidden items that only show while the search is their passphrase.
- Killphrases that quietly delete an item from the vault as soon as they're searched for.
- If you turn it on, 10 wrong App Lock Passwords in a row erase every vault.
- Hide While Recording, on by default, covers Vault while the screen is recorded, mirrored or shared, and Apple's keyboard learns nothing typed into Vault.

### Backups

- Encrypted PDF backups to print, or to save anywhere, restored from the file or by scanning their QR codes. In plain text, a backup shows only that it's a Vault backup, when it was made, and a hint if you write one.
- Automatic encrypted backups to a folder you choose, such as one in iCloud Drive, whenever your items change.
- Moving the vault to another iPhone or iPad with QR codes, with no file saved.
- Every export is the whole vault, encrypted with its backup password. There's no unencrypted export.

### Privacy

- No servers, no accounts, no sync, no analytics and no network requests.
- Your iPhone's own backups, to iCloud or a computer, include Vault's data, as they do other apps'. Set an App Lock Password to encrypt the vault, on the iPhone and in those backups.

Every promise, the code that keeps it, the test that pins it, and its limits are in [`docs/security-model.md`](./docs/security-model.md).

## Tenets

- [x] **Platform native**: it should look like Apple made this app.
- [x] **Modern**: we should use modern features and push for fast deprecations.
- [x] **Open source**: no binary code or obfuscated stuff in the app. A few build tools are prebuilt binaries, pinned by checksum.
- [x] **Robust**: test-driven development, modular PRs/commits.
- [x] **Duress-resistant**: see [`MANIFESTO.md`](./MANIFESTO.md) for the security principles that govern what Vault will and will not do.

## Development tenets

- [x] **Tested**: high level of test coverage, mockolo for mocking, Swift Testing, snapshot tests and UI tests
- [x] **Safe**: Swift 6 concurrency
- [x] **Modern**: iOS 26, SwiftUI, Structured Concurrency
- [x] **Availability**: iPhone & iPad Support
- [x] **Modular**: Swift Package w/ multiple targets
- [x] **Resilient**: everything should be versioned, we never need to break old clients, old backups should always be able to be restored

## Security

[`docs/security-model.md`](./docs/security-model.md) lists every security and privacy promise Vault makes, the code that keeps it and the test that pins it, and the limits Vault accepts.
[`MANIFESTO.md`](./MANIFESTO.md) has the principles behind them, and [`docs/on-device-encryption.md`](./docs/on-device-encryption.md) the design of the encrypted vault.

To report a security problem, see [`SECURITY.md`](./SECURITY.md). Please don't open a public issue.

## Contributing

Development takes place in `/Vault`, so take a look in there.
As soon as we are able, we will be dropping the xcodeproj project wrapper and going all-in on the Swift Package Manager.

- `Vault.xcworkspace` what you should open
- `/Vault` Swift Package that defines targets used by the app, build settings, tooling.
- `/VaultApp` minimal wrapper that packages this into an executable application.

### Validation

There is no hosted CI. Changes are validated on the developer's Mac, and the result is posted to the commit on GitHub as the **Validate (local)** status check. `main` requires that check, so a PR can't be merged until its latest commit has passed.

1. Install [Bun](https://bun.com), then run `bun install` at the root of the repo, once per clone. It installs [local-check](https://github.com/badbundle/local-check), the tool that does the validating, and enables its pre-push hook.
2. Commit your changes, then run `make validate` from `/Vault`.

The checks are in [`local-check.config.ts`](./local-check.config.ts). local-check checks out the exact commit into a separate worktree, so uncommitted changes and your usual DerivedData can't affect the result. With Xcode 27.0, it then runs:

- `make lint`;
- the Fastlane config check, which is skipped, and noted on the check, if the Ruby version in `.ruby-version` isn't installed;
- a build and full run of the `iOSAllTests` test plan on a throwaway iPhone 18 Pro Max / iOS 27.0 simulator, created for the run and deleted afterwards;
- a build and run of the UI tests, the `VaultAppUITests` scheme, on the same simulator.

If the commit is already on GitHub, the result is posted straight away. Otherwise it's stored, and the pre-push hook posts it when you push, so you can validate before or after pushing. Every new commit needs validating again. Logs are kept in `.git/local-check/logs/`.

The check is self-attested: it records that the commit passed on the machine that posted it, rather than on independent CI.

### Issues

Issues are tracked in [Trackslash](https://trackslash.com/badbundle/projects/VAULT), in the `VAULT` project owned by `badbundle`. Along with the commit history, it's the source of truth for the project's issues and progress: what's open, what's in progress and what's done. A bug, a follow-up or a planned change goes there, not in a TODO comment or a file in the repo. The repo has no GitHub Issues.

The project is public: anyone can read it, and anyone signed in to Trackslash can open an issue. Agents can read and update it through Trackslash's MCP server. Issues are referred to by their ref, such as `VAULT-60`.
