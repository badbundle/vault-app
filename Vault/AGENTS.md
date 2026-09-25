# Project Guidelines

## Security Principles

Read [`../MANIFESTO.md`](../MANIFESTO.md) before proposing or implementing any feature that touches killphrases, search passphrases, lock state, authentication, telemetry, backups, exports, or anything in the Danger Zone. The manifesto is normative — when a proposed change conflicts with it, the manifesto wins unless it is amended first via a dedicated `MANIFESTO:` PR.

## Testing

### Test Device Configuration

Use the simulator configuration specified in `README.md` for all builds and tests.

## Committing

Before every commit, run `make format` and `make lint` from the `Vault/` directory to ensure code is properly formatted and passes linting.

## Validating a Pull Request

There is no hosted CI. `main` only accepts a PR whose latest commit has the **Validate (local)** status check, and only `make validate` posts it (see [Validation](../README.md#validation)). The checks it runs are in [`local-check.config.ts`](../local-check.config.ts).

- If `bun install` hasn't been run in this clone, run it at the root of the repo first.
- Commit first, then run `make validate` from the `Vault/` directory. It validates the committed `HEAD` in a clean worktree, so uncommitted changes aren't covered.
- Run it again after every new commit on a PR branch: each commit needs its own check.
- If it fails, fix the problem, commit, and validate the new commit. Never post, edit or fake the status by hand (for example with `gh api .../statuses`), and don't work around a failing test to get a green check.
- It takes several minutes. Tell the user whether it passed, and if it didn't, which check failed and where its log is.
