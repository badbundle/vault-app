# Repo Guidance

This is the top-level guidance file. The repo contains a Swift Package and a thin app wrapper.

## Primary working directory

Day-to-day development happens in [`Vault/`](./Vault). When working on code, switch into that directory and use [`Vault/AGENTS.md`](./Vault/AGENTS.md) as the primary guide — it specifies the simulator configuration, the format/lint commands to run before every commit, and any other project-level conventions.

This root-level file only covers things that apply across the whole repo (the Swift Package, the `VaultApp` wrapper, and the workspace).

## Security principles

Read [`MANIFESTO.md`](./MANIFESTO.md) before proposing or implementing any feature that touches killphrases, search passphrases, lock state, authentication, telemetry, backups, exports, or anything in the Danger Zone. The manifesto is normative — when a proposed change conflicts with it, the manifesto wins unless it is amended first via a dedicated `MANIFESTO:` PR.

## Validation

There is no hosted CI. Before a PR can merge into `main`, its latest commit needs the **Validate (local)** status check, which is posted by running `make validate` in `Vault/`. See [Validation](./README.md#validation) in the README and the rules in [`Vault/AGENTS.md`](./Vault/AGENTS.md).

## Layout

- [`Vault/`](./Vault) — Swift Package with all targets, tests, and tooling. Open `Vault.xcworkspace` to work on it.
- [`VaultApp/`](./VaultApp) — minimal executable wrapper around the package.
- [`fastlane/`](./fastlane) — release tooling.
