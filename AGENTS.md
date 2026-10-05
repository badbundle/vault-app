# Repo Guidance

This is the top-level guidance file. The repo contains a Swift Package and a thin app wrapper.

## Primary working directory

Day-to-day development happens in [`Vault/`](./Vault). When working on code, switch into that directory and use [`Vault/AGENTS.md`](./Vault/AGENTS.md) as the primary guide — it specifies the simulator configuration, the format/lint commands to run before every commit, and any other project-level conventions.

This root-level file only covers things that apply across the whole repo (the Swift Package, the `VaultApp` wrapper, and the workspace).

## Security principles

Read [`MANIFESTO.md`](./MANIFESTO.md) before proposing or implementing any feature that touches killphrases, search passphrases, lock state, authentication, telemetry, backups, exports, or anything in the Danger Zone. The manifesto is normative — when a proposed change conflicts with it, the manifesto wins unless it is amended first via a dedicated `MANIFESTO:` PR.

[`docs/security-model.md`](./docs/security-model.md) lists every security and privacy promise Vault makes, the code that keeps it and the test that pins it, with the limits Vault accepts. A change that adds, changes or breaks a promise updates it in the same PR. Security problems are reported privately, as [`SECURITY.md`](./SECURITY.md) says, never in an issue, a PR or Trackslash.

All of Vault's encryption uses Apple's CryptoKit, never another library's or our own, so that every build can tell App Store Connect it needs no export compliance documentation. Key derivation, hashing and HMAC aren't encryption. [`docs/export-compliance.md`](./docs/export-compliance.md) has the reasoning, and what to do if Vault ever needs other encryption.

## The Mac app

The native Mac app (VAULT-101) is designed in [`docs/mac-app.md`](./docs/mac-app.md): its decisions, how each iOS protection works on the Mac, its packaging and sandbox, and which modules build for both platforms. Read it before working on the Mac app, or on making a shared module build for macOS, and update it in the same PR if what you find changes the design.

## Issues

Issues are recorded in Trackslash, in the `VAULT` project owned by `badbundle`, through its MCP server. Look there for what's open and in progress, and record a bug, a follow-up or a planned change there rather than in a TODO comment, a file in the repo or a PR body alone. Refer to an issue by its ref, such as `VAULT-60`. See [Issues](./README.md#issues).

## Validation

There is no hosted CI. Before a PR can merge into `main`, its latest commit needs the **Validate (local)** status check, which is posted by running `make validate` in `Vault/`, using the checks in [`local-check.config.ts`](./local-check.config.ts). See [Validation](./README.md#validation) in the README and the rules in [`Vault/AGENTS.md`](./Vault/AGENTS.md).

## Layout

- [`Vault/`](./Vault) — Swift Package with all targets, tests, and tooling. Open `Vault.xcworkspace` to work on it.
- [`VaultApp/`](./VaultApp) — minimal executable wrappers around the package: the iOS app (`VaultApp`) and the Mac app (`VaultMacApp`).
- [`fastlane/`](./fastlane) — release tooling.
