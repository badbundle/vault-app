# Vault Manifesto

This document records the security principles that govern what Vault will and will not do. It binds every contributor — human or AI. When a proposed feature conflicts with the manifesto, the manifesto wins unless the manifesto itself is amended first.

## Core Principle

Vault protects its users under duress, not only from remote attackers.

A meaningful fraction of Vault's threat model is a person who has physical access to the user and is coercing them to unlock the app — at a border, in custody, during a robbery, inside an abusive relationship. The user's own cooperation cannot be assumed.

Convenience features that would help legitimate users but also lower the cost of coerced data exposure are rejected. We accept friction for the legitimate user as the price of denying it to the coercer.

## Worked Example: Why "Clear All Killphrases" Was Rejected

Vault supports per-item killphrases: a user types the phrase into the search bar and the item is silently deleted. The intended use is duress — the user is being forced to unlock the app and quietly destroys the most sensitive items in the process.

A natural feature request is a "Clear All Killphrases" button in the Danger Zone for users who have forgotten one of their phrases and worry about accidental deletion while searching. The button would not delete any data; it would only blank the `killphrase` field on every item.

We rejected it.

A coercer who knows the app's feature surface can give one instruction — "open Danger Zone, tap Clear All Killphrases, authenticate" — and neutralise the entire defence in a single tap. Without the bulk action the coercer must know which items are protected and force per-item edits, which is high friction, easy to miss items, and easy for the user to claim ignorance about. The convenience for the forgetful legitimate user (who can already clear a killphrase by editing the item directly) does not justify destroying that asymmetry.

The corollaries below generalise this decision.

## Corollaries

### C1. No bulk operations on safety-critical fields.

The killphrase, search passphrase, and lock-state fields are edited per-item only. There is no "clear all," no "disable all," no multi-select sweep. The friction is the feature.

### C2. No oracle channels around duress-protected operations.

Operations on killphrase or related fields must not reveal anything beyond their intended effect. No match and an internal failure are indistinguishable, and a match shows nothing but the deletion itself. Errors are never thrown, logged, or measured in a way that confirms phrase validity. See commit 5fb920f0 (killphrase oracle in vault-store deletion) for the canonical fix and the reasoning preserved in `VaultStoreKillphraseDeleter`'s documentation.

### C3. No telemetry on duress features.

No analytics, no crash report payload, no log line, no metric — even hashed or aggregated — may record the presence, count, length, or value of killphrases or related fields. An aggregate like "12% of items have killphrases" is enough to confirm to an attacker that the feature is in use on this device.

### C4. Device authentication does not authorise removal of deniability features.

If the user can be coerced into unlocking the vault, they can be coerced into passing a biometric or PIN prompt. Device auth is the right gate for the unattended-device threat. It is not a gate against the coerced-user threat. Adding `validateAuthentication` to a dangerous action does not make that action safe to add.

### C5. No enumeration UI for duress features.

The app does not present a list of "items with a killphrase," a badge on protected items, a settings counter, or any visualisation that lets an attacker locate the protected items in one screen. A user who needs to audit their own setup does so per-item, in the same flow they used to set the field.

### C6. Destructive deniability changes have no undo and no in-app audit log.

Undo creates a recovery path that an attacker can demand. An in-app audit log creates a re-discovery oracle ("you cleared three killphrases two minutes ago — which items?"). Once a killphrase or item is gone from the device, the device has no memory that it ever existed. Backups made before the deletion are the one exception: they still hold what they held, encrypted, and restoring one always needs its backup password, never just device authentication (C4).

### C7. Blast-radius-reducing protections default to on.

When a setting reduces the data exposed by a single mistake — clipboard scoping, autofill restrictions, hiding the app while the screen is recorded — the default is the protective value. Opt-out is allowed; opt-in is not. See commit e930b05a (Universal Clipboard restriction) for an example of this in practice.

### C8. Per-item friction is intentional, not a bug to be smoothed.

If a workflow is annoying for a legitimate user, it is also annoying for a coercer reading instructions off the screen and watching the user execute them. Tickets that propose "let's reduce the steps to do X to sensitive data" should be evaluated against this corollary before being scoped.

### C9. Discoverability of duress features is intentionally asymmetric.

Legitimate users learn about killphrases through documentation, onboarding when first enabling the feature, and the FAQ. The in-product UI does not advertise "this app supports killphrases" to a casual inspector flipping through screens. A field that only appears once the user has entered an edit screen for an item, with no banner or settings-level toggle pointing at it, is the right shape.

### C10. Backups, exports, and device-transfer payloads preserve the same threat model.

Killphrase fields and related metadata must not appear in any form a recipient can preview without first decrypting the vault. Export tooling, debug bundles, and transfer payloads are reviewed against this rule before shipping.

## Amending This Document

Changes to this manifesto require a dedicated pull request titled `MANIFESTO: …` with the rationale in the PR description. Bundling manifesto changes inside an unrelated feature PR is forbidden; the principles must be amended openly and on their own merits, not as a side-effect of work that is incidentally constrained by them.
