# Project Guidelines

## Security Principles

Read [`../MANIFESTO.md`](../MANIFESTO.md) before proposing or implementing any feature that touches killphrases, search passphrases, lock state, authentication, telemetry, backups, exports, or anything in the Danger Zone. The manifesto is normative — when a proposed change conflicts with it, the manifesto wins unless it is amended first via a dedicated `MANIFESTO:` PR.

Keep [`../docs/security-model.md`](../docs/security-model.md) in step: a change that adds, changes or breaks a security or privacy promise updates its row, and a new test that pins one is named there.

## Testing

### Test Device Configuration

Use the simulator configuration specified in `README.md` for all builds and tests.

### UI Tests

The UI tests are in `VaultApp/VaultAppUITests`, a target of the app's Xcode project, as a Swift package can't hold UI tests. They launch the app on the in-memory demo vault (`-screenshot-scene feed`, see `ScreenshotMode`), or, for the lock, on a vault the app prepares in a directory, defaults and keychain items of its own (`-ui-test-vault`, see `UITestVault`), so they never touch the simulator's own vault. They find elements by accessibility identifier rather than by text. To run only them, from the root of the repo: `xcodebuild test -workspace Vault.xcworkspace -scheme VaultAppUITests -destination 'id=<simulator UDID>' -skipMacroValidation -skipPackagePluginValidation`.

The Mac app's UI tests are in `VaultApp/VaultMacAppUITests`, with their own `VaultMacAppUITests` scheme, and its tests that run inside the launched app are in `VaultApp/VaultMacAppTests` (the `VaultMacApp` scheme). Run them with `-destination platform=macOS`. Development builds of the Mac app are signed with the team's Apple Development certificate and the "Vault Mac Development" provisioning profile, which the Mac's keychain needs (see Signing in [`../docs/mac-app.md`](../docs/mac-app.md)). They launch on a vault of their own with `-ui-test-vault fresh` (see `VaultMacUITestVault`).

## Committing

Before every commit, run `make format` and `make lint` from the `Vault/` directory to ensure code is properly formatted and passes linting.

## Validating a Pull Request

There is no hosted CI. `main` only accepts a PR whose latest commit has the **Validate (local)** status check, and only `make validate` posts it (see [Validation](../README.md#validation)). The checks it runs are in [`local-check.config.ts`](../local-check.config.ts).

- If `bun install` hasn't been run in this clone, run it at the root of the repo first.
- Commit first, then run `make validate` from the `Vault/` directory. It validates the committed `HEAD` in a clean worktree, so uncommitted changes aren't covered.
- Run it again after every new commit on a PR branch: each commit needs its own check.
- The Mac UI tests can't run while the Mac's screen is locked. Only when the user has asked to bypass them, run `VAULT_SKIP_MAC_UI_TESTS=1 make validate`, and tell them that check was skipped, so a full run can follow once the Mac is unlocked.
- If it fails, fix the problem, commit, and validate the new commit. Never post, edit or fake the status by hand (for example with `gh api .../statuses`), and don't work around a failing test to get a green check.
- It takes several minutes. Tell the user whether it passed, and if it didn't, which check failed and where its log is.
