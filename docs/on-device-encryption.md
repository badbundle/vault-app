# Encrypting the vault on device with the app lock password

Feasibility study and design for VAULT-26. It also covers what the app lock password (VAULT-22), the duress
vault (VAULT-23) and erasing after failed attempts (VAULT-34) need from storage.

## Verdict

**Feasible without compromises**, measured against VAULT-26's "What no compromises means". The catch is how:
the encrypted vault doesn't use SwiftData at all.

- The two SwiftData-based approaches fall short. Field-level encryption leaves counts, types, dates, order,
  killphrase flags and the tag graph readable, and two stores can be told apart by size. A custom SwiftData
  `DataStore` silently ignores `delete(model:where:)` and `@Attribute(.unique)` upserts, which the killphrase,
  delete and update paths depend on. SwiftData in memory with an encrypted file works, but unlocking a
  5,000-item vault takes 1.1 s before the password is even derived.
- The design that meets every point is a **single encrypted file of eight equal-size slots**. It holds the vault
  as plain records, which are decoded into an in-memory record store while the vault is unlocked. There's a
  random data key per vault, wrapped by a key derived from the password with Argon2id. Every change is written
  as an atomic, verified replacement of the whole file.
- Measured on an M5 Max: deriving the key takes about 170 ms, trying all eight slots takes 0.02 ms, and loading
  a 1,000-item vault takes about 9 ms. Saving a change takes about 17 ms at 1,000 items and 85 ms at 5,000,
  including a full `F_FULLFSYNC`.
- Users who never set an app lock password keep today's SQLite store, unchanged.

What Bradley has to accept is listed under [Consequences](#consequences-to-accept). The main ones:

- While the password is on, widgets can't show codes and QuickType suggestions go away. AutoFill asks for the
  password in its own sheet.
- The password has to be a real password. Anyone who copies the file can guess offline at the speed the KDF
  allows.
- A forgotten password means restoring from a backup.
- Turning the password off keeps the encrypted file, with its key wrapped by a device key. It doesn't convert
  back to SQLite, because that can't be done without destroying the other slots.

Two limits apply to any deniable design, not just this one. They're explained in
[Residual limits](#residual-limits):

- Someone holding copies of the file from two different times can see which slot changed.
- A coercer who nests "make duress database" more than five levels deep eventually puts the real vault at risk.
  No finite design can prevent that without leaving a mark in the duress vault they're given.

## Contents

1. [What's on disk today](#whats-on-disk-today)
2. [Approaches evaluated](#approaches-evaluated)
3. [Design](#design)
4. [Duress vault (VAULT-23)](#duress-vault-vault-23)
5. [Erasing after failed attempts (VAULT-34)](#erasing-after-failed-attempts-vault-34)
6. [Widgets, AutoFill and QuickType](#widgets-autofill-and-quicktype)
7. [Backups, killphrases and everything else](#backups-killphrases-and-everything-else)
8. [What's readable at rest](#whats-readable-at-rest)
9. [Residual limits](#residual-limits)
10. [Test strategy](#test-strategy)
11. [Consequences to accept](#consequences-to-accept)
12. [Sub-issues](#sub-issues)
13. [Appendix: measurements](#appendix-measurements)

## What's on disk today

These are facts from the code and from the prototypes described in the [appendix](#appendix-measurements).

- **The vault** is a SwiftData SQLite store, `vault-primary.sqlite` with `-wal` and `-shm`, in the App Group
  container (`VaultSharedStorage`). The app, the AutoFill extension and the widget extension all open it. Every
  field is plaintext, except the payloads of items that have their own password (`encryptedItemDetails`).
- **Killphrase residue.** A killphrased item that has already been checkpointed into `vault-primary.sqlite`
  stays there in plaintext until the next WAL checkpoint. The delete only goes to the WAL. The app keeps the
  store open all session, and SQLite only checkpoints automatically at about 1,000 WAL pages, so that window
  can be long. After a checkpoint the bytes are gone from the live files. This was measured in the `forensics`
  prototype.
- **Device backups.** The App Group container is included in iCloud and Finder device backups, so the plaintext
  store is too. Without Advanced Data Protection, iCloud Backup is readable by Apple.
- **Readable flags.** Non-null `killphraseDigest` and `searchPassphraseDigest` columns show which items have a
  killphrase or a search passphrase to anyone who can read the file. That's the enumeration C5 forbids in the UI.
- **The QuickType identity store** (`ASCredentialIdentityStore`) holds the issuer, account name and item UUID
  of every visible OTP item, outside the app's sandbox.
- **Widgets.** WidgetKit archives the rendered timeline entries (issuer, account name, current code) in system
  storage. It also keeps the configured `OTPWidgetItemEntity`, which has the issuer and account name.
- **Pending rehash files.** `vault-primary.pending-killphrase-rehash.json` and the search passphrase equivalent
  hold plaintext phrases between a V1→V2 or V2→V3 migration and the first unlock after it.
- **Failed-open archives.** When the store can't be opened, `PersistedLocalVaultStoreFactory` moves it into
  `vault-primary.failed-open-<timestamp>/`. Those are full plaintext copies of the vault.
- **Settings.** The last backup event (dates and a payload hash) and the auto-backup configuration are in
  `UserDefaults`. The backup password's derived key and a "backup password is set" record are in the keychain.
  None of these identify items.

## Approaches evaluated

### 1. Field-level encryption in the SwiftData store

Encrypt fields in `PersistedVaultItemEncoder` and `PersistedVaultTagEncoder`, and decrypt in the decoders.

**Falls short:**

- **Queries.** Every content predicate in `PersistedLocalVaultStore` would have to move into memory. That
  includes `localizedStandardContains` over the description, note title, note contents, issuer, account and
  encrypted title, and the tag filter over the relationship. So every unlock would decrypt everything anyway,
  which is the cost of whole-store encryption, while still keeping SQLite's leaks.
- **What stays readable:**
  - Row counts per entity: how many OTP codes, notes, encrypted items and tags.
  - The item–tag join table: which items share a tag.
  - Ciphertext lengths, such as note lengths.
  - Whatever is left unencrypted for sorting and filtering: `relativeOrder`, dates, `visibility`,
    `searchableLevel`, `lockState`. That reveals, for example, how many items are hidden behind a search
    passphrase.
  - Nullability of the digest columns: which items have killphrases.
  - Core Data's `Z_PRIMARYKEY`: how many items were ever created.
  - Free pages and the WAL.
- **Duress.** Two SQLite stores differ in size, page count and row counts. They can't be made
  indistinguishable.
- **Password changes.** It works only if the field key is a wrapped data key, which is fine. The other problems
  remain.

### 2. A custom SwiftData `DataStore`

The iOS 18 `DataStore` API with a whole-file backend. The encryption itself is orthogonal. The `datastoreprobe`
prototype ran the app's schema (a copy of `PersistedSchemaV3`) and the app's real predicates against a
minimal file store:

| Check | Result |
| --- | --- |
| Insert 100 items with tags and details, reopen | OK: relationships survive, with `copy(persistentIdentifier:remappedIdentifiers:)` |
| Feed, tag filter, search and killphrase-candidate predicates | OK, through `preferInMemoryFilter` and `preferInMemorySort` |
| `delete(model:where:)`, used by item delete, tag delete, **killphrase delete** and `deleteVault()` | **Silent no-op.** Nothing is deleted and no error is thrown. With `DataStoreBatching`, a predicate delete can't be handed back (`preferInMemoryFilter` is thrown to the caller), so the store would have to evaluate model predicates itself. |
| `@Attribute(.unique)` upsert, which is how `update(id:item:)` works | **Not enforced.** Each edit leaves a duplicate item. |
| `fetchLimit` | Ignored by the in-memory fallback. |
| Migration plans | The store's own problem. |

**Falls short:** it would mean reimplementing a database's semantics (batch deletes, cascades, uniqueness,
limits, migrations) under a young API with silent failure modes. Crash safety would depend on framework
internals we can't see. A killphrase that silently doesn't delete is exactly the failure Bradley is worried
about.

### 3. SwiftData in memory, with an encrypted file on disk

On unlock, decrypt the file and rebuild an in-memory `ModelContainer`. That's the configuration all 107
`PersistedLocalVaultStoreTests` already run against. After each write, snapshot every model into a payload,
encrypt it and replace the file.

**It works, and query semantics are reused unchanged.** But:

- **Unlock time grows superlinearly.** On the M5 Max, loading (reading, decrypting, decoding, rebuilding the
  in-memory store and running the first feed query) took 18 ms at 100 items, 175 ms at 1,000 and
  **1,142 ms at 5,000**. The tag relationship's inverse bookkeeping is quadratic. Assigning tags from the tag
  side brings 5,000 items down to 816 ms. SwiftData's floor, with no relationships at all, is about 80 µs an
  item. Add the key derivation and slower iPhones, and vaults above roughly 2,000–3,000 items miss "about a
  second".
- **Every save snapshots SwiftData.** That takes 69 ms at 1,000 items (24 ms with relationship prefetching) and
  330 ms at 5,000.
- **Memory can get ahead of disk.** It isn't safe to snapshot before `save()`, because it isn't clear that
  pending batch deletes are visible to fetches. After a failed file write, the whole container has to be
  rebuilt.

**Falls short** on unlock speed for large vaults, and leaves the encrypted path depending on SwiftData
lifecycle details.

### 4. Encrypted record store (recommended)

The same whole-file approach, but the unlocked vault is held as plain `VaultRecord` values, a field-for-field
mirror of the persisted schema, in an actor that implements the existing store protocols. No SwiftData is
involved.

- **Loading a 1,000-item vault takes about 9 ms**: decompressing 0.5 ms, decoding 5.7 ms, and filtering and
  sorting the feed 2.5 ms. At 5,000 items it takes about 45 ms.
- **Saving takes about 17 ms at 1,000 items**: encoding, compressing, sealing and replacing the whole 8 MiB file
  with `F_FULLFSYNC`. At 5,000 items it takes about 85 ms.
- **Search takes 2 ms at 1,000 items** and 10 ms at 5,000, against 4.7 ms and 33 ms for today's SQLite store.
- **New state is published only after the file is committed**, so memory is never ahead of disk.
- **The cost is a second implementation of the store's query and mutation semantics.** That's contained by
  sharing the record encoder and decoder with the SwiftData store, and by running the existing store test suite
  against both engines, plus a differential test (see [Test strategy](#test-strategy)).

### 5. Also considered

- **Reusing the backup format as-is.** The pipeline shape (JSON, compress, AEAD) is right, but the format itself
  doesn't fit:
  - It drops `showInQuickType` and `previewMode`. `VaultBackupItemDecoder` resets them to `true` and
    `.titleAndFirstLine`. This is also a live bug: restoring a backup turns QuickType back on for items the user
    opted out, which C7 cares about. See [sub-issue 14](#sub-issues).
  - It goes through domain decoding, so an item that fails to decode can't be carried.
  - It uses lzma: 105 ms at 1,000 typical items, 546 ms with heavy notes.
  - It uses CryptoSwift's AES-GCM: about 30 ms per MiB, against about 0.1 ms for CryptoKit.
  - It derives the key directly from the password. There's no data key to rewrap.
  - It pads by a random amount rather than to a fixed size.
- **SQLCipher.** A C dependency that SwiftData can't sit on (Core Data would need an `NSIncrementalStore` shim).
  It still leaks page counts and WAL activity, and gives nothing for duress.
- **A device-bound secret** (a keychain `ThisDeviceOnly` pepper, a Secure Enclave key, or a keychain item with
  `.applicationPassword`). It would stop offline guessing from a copied file. But the vault could no longer be
  restored to a new iPhone from a device backup, which is a new data-loss path. `.applicationPassword`'s
  derivation and rate limiting are also undocumented. Rejected for v1. It could come back later as an explicit
  opt-in.
- **One file per item.** Leaks the count and sizes.
- **iOS Data Protection alone** (today). It only protects while the device is locked. It doesn't help against a
  coerced device unlock, forensic extraction of an unlocked phone, or iCloud Backup.

## Design

### Overview

```
                      ┌────────────────── App Group container ───────────────────┐
  no password ever →  │ vault-primary.sqlite (+wal, shm)      ← unchanged today    │
                      │                                                          │
  password set     →  │ vault-slots.v1   header │ slot 0 │ slot 1 │ … │ slot 7    │
                      │ vault-slots.lock  (flock, empty)                         │
                      │ vault-storage-state.json  (mode + transition journal)    │
                      └──────────────────────────────────────────────────────────┘

  unlock:  password ──Argon2id(salt)──► K_pw ──HKDF(slot nonce)──► W_i ──open──► data key K
           K ──open body──► lzfse ──► JSON ──► [VaultRecord] ──► RecordVaultStore (in memory)
```

### Storage modes

| Mode | When | Store | Unlock |
| --- | --- | --- | --- |
| `plain` | No app lock password has ever been set, or after an erase | Today's SQLite store | Device authentication only (VAULT-21) |
| `encrypted(password)` | App lock password set | Slot file | Device authentication, then the password |
| `encrypted(deviceKey)` | Password turned off after being on | Slot file, with the open vault's key wrapped by a keychain device key | Device authentication only |

The mode lives in `vault-storage-state.json`, written atomically with `F_FULLFSYNC`, together with the journal
for in-progress transitions. It isn't secret: the lock screen already shows whether a password is set.

`plain` exists so that users who never opt in carry no new risk. The first time the password is set, there's a
one-time, verified conversion. After that, turning the password on and off only rewraps keys.

### Key hierarchy

- `K_pw` = Argon2id(password, `salt`, params from the header): 32 bytes, derived once per unlock attempt.
- `W_i` = HKDF-SHA256(ikm `K_pw`, salt `slotNonce_i`, info `"vault.slot.wrap.password.v1"`) for each slot `i`.
  In `encrypted(deviceKey)` mode it's HKDF-SHA256(ikm `D`, salt `slotNonce_i`,
  info `"vault.slot.wrap.device.v1"`), where `D` is a 256-bit keychain item. It's migratable, so a device backup
  restores it with the file, and `.whenUnlocked` until sub-issue 11 decides what widgets need.
- `K_i`, the data key, is 256 random bits per vault. It's sealed under `W_i` together with the body length, a
  generation counter and the time it was wrapped.
- The body is sealed under `K_i` with AES-256-GCM (CryptoKit) and a fresh nonce on every save.

**Changing the password** derives the new `K_pw`, reseals `K_i` under the new `W_i` and rewrites the file. The
body is untouched. Every save re-encrypts the body anyway, because the whole vault is a few hundred KiB.

The salt and KDF parameters are **shared by all slots** and fixed for the life of the file. That lets one
derivation test every slot. It also means the parameters can't be raised later for vaults the app can't open
(see [Residual limits](#residual-limits)).

### Key derivation

**Argon2id, m = 64 MiB, p = 1, t = 8 provisionally** (about 170 ms on an M5 Max). It comes from the PHC
reference implementation, vendored as a C target. The reference is CC0 or Apache-2.0, about 3,800 lines, and
compiles without warnings.

- **Calibrate `t` before shipping.** On the oldest supported iPhone, derivation should take no more than about
  0.4–0.5 s. The parameters are fixed per file, so this has to be settled before the format ships.
- **Memory is 64 MiB** so the AutoFill extension can derive the key. Bitwarden warns about iOS AutoFill above
  64 MiB of Argon2id memory ([Bitwarden: KDF algorithms](https://bitwarden.com/help/kdf-algorithms/)). A CLI
  process deriving with 64 MiB peaks at a 75 MB footprint. If the AutoFill extension can't sustain that, drop to
  32 MiB and double `t`.
- **Why not scrypt.** Measured on the M5 Max, Argon2id fills 64 MiB three times in 68 ms. As a rough
  memory-bandwidth bound, one Argon2id guess at t = 8 (about 1.5 GiB of memory traffic) moves about four times as
  many bytes as scrypt N = 2¹⁶, r = 8, p = 3 (about 384 MiB) does in about the same time (197 ms), and Argon2id
  resists time–memory trade-offs better. A GPU guessing Argon2id at t = 8 is bandwidth-bound at roughly 650
  guesses per second per TB/s. That's a rough upper bound, not a measurement.
- **Fallback, if Bradley doesn't want a C target:** scrypt N = 2¹⁶, r = 8, p = 3 (64 MiB), with our own
  optimized ROMix. That's about 100 lines. The prototype matches RFC 7914's test vectors and CryptoSwift's
  output, and is 2.4–2.7× faster than CryptoSwift. CryptoSwift itself, in the same time, would buy only about
  40% of the attacker cost.
- It's added as `VaultKeyDeriver.Signature.appLockV1`, next to the backup and item derivers.

For comparison, the existing per-item password KDF (`Item.Secure.v1`) takes 733 ms on the M5 Max. The backup's
`Secure.v1` spends about 13 s on PBKDF2 alone there, and minutes on an iPhone.

### On-disk format (`vault-slots.v1`)

One file: a 128-byte plaintext header followed by `slotCount` slots of `slotSize` bytes each.

```
Header (plaintext; same layout on every install, only the salt differs)
  0   8  magic "VLTSLOTS"
  8   2  format version = 1
  10  2  slot count = 8
  12  4  slot size in bytes (1 MiB × 2^k)
  16  2  KDF id (1 = Argon2id)
  18  4  Argon2 memory KiB      22 4  Argon2 iterations      26 1  Argon2 lanes
  32  32 salt
  64  64 reserved, zero

Slot i (slotSize bytes; every byte looks random)
  0    32  slot nonce
  32   84  key box   = AES-GCM(W_i, AAD = header ‖ i ‖ slot nonce): 12 nonce + 56 sealed + 16 tag
                        [ K_i (32) ‖ body length (8) ‖ generation (8) ‖ wrapped-at ms (8) ]
  116  …   body box  = AES-GCM(K_i, AAD = header ‖ i ‖ slot nonce)
                        [ payload version (4) ‖ compression (4) ‖ compressed length (8) ‖ payload ‖ zero fill ]
  …        random fill up to slotSize (only after another slot grew the file)
```

- **Unused slots** are random bytes. AES-GCM output is indistinguishable from random, so an empty slot, a real
  vault and a duress vault look the same.
- **The header is authenticated** as AAD, so tampering with the KDF parameters or the salt makes every slot fail
  closed.
- **Padding.** Each vault writes its body to fill its slot, so a slot's contents reveal nothing about its size.
- **Slot size** starts at 1 MiB, which holds about 3,500 typical items or 1,400 heavy-note items once
  compressed. It doubles when any vault outgrows it. On growth, the vault being written re-seals its own slot at
  the new size, and every other slot is copied byte for byte with random fill appended. Their key box carries
  their real body length, so they still open. Slots never shrink, because the app can't know what the others
  hold.
- **Total size** is 8 MiB at the minimum. Rewriting it takes 6–7 ms on the M5 Max. At 16 MiB it takes 9 ms.
- **File protection** is `.complete` in password mode: only the foreground app and the AutoFill sheet read it,
  and both run while the device is unlocked. In `encrypted(deviceKey)` mode, use the same class as today's
  store, so widgets behave as they do now once [sub-issue 11](#sub-issues) lands.
- **Device backups** keep including the file. It's ciphertext, and it's portable: the password plus the file
  are enough to restore on a new iPhone.

### Payload

JSON, with dates as milliseconds since 1970 and data as base64, compressed with lzfse. The body header
records the algorithm, so it can change later.

- lzfse decompresses fastest, which is what unlocking waits on: 0.5 ms at 1,000 items and 3 ms at 5,000,
  against 4 ms and 21 ms for zlib.
- Compress with the Compression framework's streaming API. `NSData`'s one-shot lzfse took 155 ms to compress
  the 4.4 MiB payload at 5,000 items, against 49 ms for zlib.

```
{ "version": 1,
  "items": [VaultRecord],   // every PersistedSchemaV3.PersistedVaultItem field + details, raw strings
  "tags":  [TagRecord],
  "vault": { "duressSlots": [UInt8] /* VAULT-23 */, "settings": { /* per-vault settings, VAULT-23 */ } } }
```

- **`VaultRecord` mirrors the persisted schema, not the domain model.** Migration is then a field-for-field copy
  that can't fail, and an item that fails domain decoding in SQLite today survives the migration byte for byte.
- **One encoder and one decoder.** `PersistedVaultItemEncoder` and `PersistedVaultItemDecoder` are refactored to
  produce and consume `VaultRecord`. The SwiftData store copies records to and from `@Model` objects.
- **Payload version.** Each version adds optional fields with defaults, and the decoder accepts every older
  version. SwiftData schema migrations don't apply to encrypted vaults.
- **A schema parity test** fails if the latest `VersionedSchema` has an attribute that `VaultRecord` doesn't
  carry. Forgetting a field would otherwise silently drop data at migration.

### Reading and writing while unlocked

`RecordVaultStore` is an actor. It implements `VaultStoreReader`, `VaultStoreWriter`, `VaultStoreReorderable`,
`VaultStoreExporter`, `VaultStoreImporter`, `VaultStoreDeleter`, `VaultStoreKillphraseDeleter`,
`VaultStoreHOTPIncrementer` and `VaultTagStore` over `[VaultRecord]` and `[TagRecord]`, keyed by id.
`EncryptedVaultStore` wraps it with the slot file. Each mutation:

1. Computes the new records from the current ones, without publishing them.
2. Takes `flock(LOCK_EX)` on `vault-slots.lock` and reads the current file. If our slot's generation isn't the
   one we loaded, another process has written it: it stops with a conflict and reloads.
3. Encodes, compresses and seals the body with generation + 1, reseals the key box, and builds the new file
   bytes with the other slots copied unchanged.
4. Writes a temp file, `.vault-slots.tmp-<random>`, and calls `F_FULLFSYNC`.
5. **Verifies** the temp file: opens our slot's key box and body from it, decodes, and compares with the new
   records.
6. Renames the temp file over `vault-slots.v1`, then `fsync`s the directory.
7. Publishes the new records in memory and releases the lock.

If any step fails, the temp file is removed, the in-memory records stay as they were, and the error is thrown.
`deleteItems(matchingKillphrase:using:)` returns `false` instead, exactly as it does for "no match" today, so C2
holds. Search, killphrase matching and search passphrase matching are all in memory.

### Crash safety

| Crash or failure during | State afterwards | Recovery |
| --- | --- | --- |
| A save, before the rename | Old file intact; maybe a stray temp file | Temp files are deleted at launch. The change was never reported as saved. |
| A save, after the rename | New file, already verified | None needed |
| Disk full, or verification fails | Old file intact | Error shown; nothing changes in memory |
| A password change | Old or new file, never a mix | Either the old or the new password works |
| Slot growth | Old or new file; one rename covers every slot | None needed |
| Enabling the password | See [Migration](#migration-plain-to-encrypted) | Journal |
| A torn write or storage fault (not expected on APFS) | A slot fails to authenticate | The file is **never** reset automatically. The failure screen offers restoring from a backup, or erasing. |

The atomicity comes from one file, one `rename`, and `F_FULLFSYNC` before it. No path overwrites the only copy
of anything. Deliberately, there's no "previous generation" file. It would keep killphrased items on disk
(MANIFESTO C6), and the verify-before-rename step already covers the failure it would guard against.

### Migration: plain to encrypted

This runs when a password is first set in VAULT-22's setup flow. Preconditions, checked before deriving
anything:

- The SQLite store opened normally (`vaultStoreLoadFailureMessage == nil`).
- Both pending rehash files are empty. The rehash services have already run at `setup()`. If entries remain,
  the migration isn't offered, because plaintext phrases would otherwise survive it.
- No `vault-primary.failed-open-*` archives exist. If they do, the flow says they'll be deleted, because they're
  plaintext copies, and asks to confirm.
- The flow shows the last backup date and nudges the user to back up first. A forgotten password means
  restoring from a backup.
- No other process is writing. The conversion holds `vault-slots.lock`, and the AutoFill extension doesn't open
  the SQLite store while the journal says `migrating`.

Steps:

1. Derive `K_pw` with a fresh salt. Choose the real vault's slot `r` uniformly at random, never a fixed index,
   and generate `K_r`.
2. Snapshot the SQLite store to `[VaultRecord]`.
3. Build the file in memory: the header, slot `r` sealed (its `duressSlots` are four random slots ≠ `r`), the
   other slots random.
4. Write the journal: `migrating(temp: name)`.
5. Write the temp file and call `F_FULLFSYNC`. **Verify** it by running the full unlock path against it with the
   password, then compare every record with the snapshot.
6. Rename it to `vault-slots.v1` and `fsync` the directory.
7. Write the journal: `encrypted(password), cleanup: plain`. This is the commit point.
8. Close the SwiftData container. Delete `vault-primary.sqlite`, `-wal`, `-shm`, the pending rehash files and
   the confirmed archives.
9. Write the journal: `encrypted(password)`. Clear the QuickType identity store, reload widget timelines, and
   switch the store session to the unlocked encrypted store.

At launch:

- Journal `migrating`, or `plain` with a stray slot file: the SQLite store was never touched and is still the
  truth. Delete the slot file and any temp files. The UI never said the password was set.
- Journal `encrypted(password), cleanup: plain`: finish deleting the SQLite files. This is idempotent.

**No step deletes the source before a verified copy is committed.**

### Turning the password off, and why it doesn't convert back

Turning the password off requires the current password (VAULT-22). It then:

1. Journals `turningOff`.
2. Reseals the open vault's key under a device-key wrap and replaces the file.
3. Sets the mode to `encrypted(deviceKey)`.

Turning it back on reverses this with the new password and the same salt. At launch, `turningOff` is resolved
by trying the device key on every slot: if a slot opens, the rewrap happened; if not, the password is still on.

Converting back to SQLite isn't offered, because it can't be done correctly:

- Converting back has to remove the slot file, which destroys every other slot. From inside a duress vault,
  "turn off the password" would then destroy the real vault. VAULT-23 says it must behave plausibly without
  touching the real vault.
- Leaving the slot file next to a new SQLite store instead would orphan it. A later "set password" would have
  to pick slots without knowing which ones hold dormant vaults.
- With the device-key rewrap, turning the password off from the real vault or from a duress vault behaves the
  same, and neither touches the other.

**Rollback story:** the SQLite store is never modified until after a verified encrypted copy is committed. After
commit, the way back is the password toggle (rewrap only) or an erase. Downgrading the app below the release
that introduces the format isn't supported. If a plain store appears while in encrypted mode (TestFlight
downgrade and back), the app offers to merge its items into the open vault instead of silently dropping them.

### Unlocking and locking

**Unlock, when a password is set.** The lock screen is VAULT-22's. The storage side:

1. Increment the persistent attempt counter (VAULT-22 and VAULT-34) **before** deriving. Force-quitting then
   can't skip a wrong attempt.
2. Start a fixed deadline for the device, set when the password is set, for example twice the measured
   derivation time.
3. Derive `K_pw` off the main actor.
4. Try **every** slot's key box, with no early exit.
5. If exactly one opens, open its body. If more than one opens, pick the most recently wrapped (see
   [same passwords](#same-passwords)). Decode it.
6. Drop `K_pw` and every `W_i`. They're CryptoKit `SymmetricKey`s, whose storage is zeroed on release. The
   Argon2 working memory is `memset_s`'d before it's freed.
7. Wait for the deadline. Then reset the counter and show the vault, or show the error.

Wrong, real and duress passwords all run the same derivation and the same eight trials, and finish at the same
deadline. What differs afterwards is decoding time, which is proportional to what the vault shows anyway.

**Lock.** This happens on background, or explicitly (VAULT-21):

- Await any in-flight write on the store actor.
- Switch the store session to `locked`.
- Drop the record store, `K_i`, the item caches and search text (`VaultDataModel.purgeSensitiveData()`, which
  gets extended to do this).

**Zeroing, honestly:**

- Keys live in `SymmetricKey` and are zeroed.
- Swift `String` and `Data` copies of decoded items can't be reliably zeroed. They're freed and eventually
  reused. Process memory isn't readable by other apps, but a forensic tool with code execution on an unlocked,
  exploited device can read a suspended process.
- The password comes from a `SecureField`. The binding is cleared after use, but the `String` isn't zeroed.

**Store session.** `VaultRoot.vaultStore` is a `static let PersistedLocalVaultStore` today. It becomes a
`VaultStoreSession` that implements the same protocols and forwards to `plain(PersistedLocalVaultStore)`,
`unlocked(EncryptedVaultStore)` or `locked`. `VaultDataModel` already takes protocol types, so it barely
changes.

## Duress vault (VAULT-23)

The format serves VAULT-23 directly:

- **Eight slots always exist.** A file with a duress vault looks exactly like one without.
- **Unlock timing is identical,** as described above.
- **Each vault is a full payload,** with its own items, tags, killphrases and per-vault settings: backup
  password, backup events, auto-backup configuration and the "backup password is set" record. VAULT-23 moves
  those from `UserDefaults` and the keychain into `payload.vault.settings`.

### Making a duress database, from any vault

Each vault's payload carries `duressSlots`, a list of L = 4 distinct slot indices that never includes its own.
The first vault, created at migration, gets four random slots ≠ `r`.

"Make duress database" from vault V, with a new password:

1. Target = `V.duressSlots[0]`, always the same slot. So making another duress vault replaces V's previous one,
   as VAULT-23 decided.
2. Create W in the target slot: an empty payload and a new data key, wrapped with the new password (same salt).
3. `W.duressSlots = V.duressSlots[1...] + [x]`, where x is random from the slots not in
   {V's slot, W's slot} ∪ `V.duressSlots[1...]`.
4. Replace the file, as for any save. V keeps working with its password.

From inside a duress vault, this behaves exactly as it does from the real vault: same steps, same timing, same
payload shape. A payload shows only "four other slots", which is true of every vault.

**The real vault is never touched for five levels of nesting.** Every entry the real vault writes excludes its
own slot, so a chain R → D1 → … → D5 never targets R.

From the sixth level, an entry chosen by a duress vault, which can't know where R is, may name R's slot. The
chance is 1/(N − L − 1) = 1/3 per creation at N = 8, L = 4. At N = 16 and L = 10 it's safe for eleven levels,
then at most 1/5 per creation, with a 16 MiB file (9 ms per save). VAULT-23 should pick N and L.

**Why no finite design does better.** From inside a duress vault, the app knows exactly what someone holding
that vault's password knows: the vault's contents.

- To avoid the real vault's slot at any depth, those contents have to identify it, directly or through a rule
  the app can compute. Anyone who decrypts the duress vault can compute the same rule and see that one slot is
  special.
- The real vault could carry an equally shaped pointer that means nothing. But it would still have to behave
  differently when it creates a duress vault: it hands on its own slot, where a duress vault hands on the pointer
  it inherited. That difference has to be recorded somewhere in its contents, and a coercer reading a duress
  vault would find it missing.

So the choice is between bounded-depth safety with clean payloads (this design) and unbounded safety with a
readable mark in every duress vault. The repository is public, so a mark would be found. This design picks clean
payloads.

### Same passwords

- A new password equal to the password of **the vault you're in** is refused: "must differ from the app lock
  password". That check is identical in every vault.
- A new password that happens to open **another** slot is accepted silently. Refusing it would be an oracle: a
  coercer could test guesses through "make duress database", bypassing the unlock delay and the VAULT-34
  counter.
- If more than one slot opens at unlock, the most recently wrapped wins. That's the vault just created, which
  matches "the new password opens a new empty vault". The older one becomes unreachable but isn't destroyed. If
  the colliding password is the real one, the coercer already knew it.

### Everything else for VAULT-23

- **Delete All Data** empties the open vault's slot and keeps the slot and its password. It's the same in every
  vault.
- **Turning the password off** rewraps the open vault only (see above).
- **Backups and auto-backup** read only the open vault. VAULT-23 must keep each vault's auto-backup destination
  and retention cleanup in that vault's settings, so a duress vault never deletes or overwrites the real one's
  backups.
- **Item dates.** Created dates inside a duress vault show how recently it was filled. That's outside storage,
  but VAULT-23's guidance should mention it.

## Erasing after failed attempts (VAULT-34)

**Erase is key destruction.** Every wrapped data key lives in `vault-slots.v1`. Erasing does the following, in
order, idempotently, and journaled so a crash mid-erase finishes at next launch:

1. Unlink `vault-slots.v1`, the temp files and the lock file.
2. Delete the keychain items: device key, killphrase and search passphrase HMAC keys, backup password and its
   record, attempt counter.
3. Clear the storage state and the per-device settings Delete All Data clears.
4. Clear the QuickType store and reload widgets.
5. Create a fresh, empty `plain` store.

Step 1 makes every vault unreadable instantly, before the rest runs.

Honest limits:

- The app can't reach iOS's effaceable storage. Freed flash blocks aren't something an app can overwrite, and
  copies in earlier device backups remain.
- Those remnants are ciphertext under the password-derived key. Erasing stops guessing **on the device**. Guessing
  against a copy taken earlier is what the KDF, and the password's strength, are for.

The counter is per device and shared by all vaults. The duress password is a correct password: it opens a slot
and resets the counter.

## Widgets, AutoFill and QuickType

| Surface | `plain` | `encrypted(password)` | `encrypted(deviceKey)` |
| --- | --- | --- | --- |
| Widgets | As today | Locked placeholder. `OTPWidgetItemEntityQuery` returns nothing. `reloadAllTimelines()` when the password is turned on, so archived timelines with codes are replaced. | As today, once [sub-issue 11](#sub-issues) lands; locked until then |
| Widget HOTP increment | As today | Unavailable | Sub-issue 11 |
| AutoFill sheet (`prepareOneTimeCodeCredentialList`) | As today | Asks for the app lock password in the sheet, derives with 64 MiB, opens the slot. Writes (HOTP) go through the same `flock` and generation check. Never Face ID alone (C4). | Sub-issue 11 |
| QuickType (`provideCredentialWithoutUserInteraction`) | As today | Identity store emptied when the password is turned on, and never written while it's on. Requests return `userInteractionRequired`. | Sub-issue 11 |

Residual: a configured widget's saved `OTPWidgetItemEntity` (issuer, account name) sits in the system's widget
configuration, which the app can't edit. Turning on the password should tell users to remove existing widgets.

## Backups, killphrases and everything else

- **Backups, exports, device transfer, auto-backup.** Unchanged. They export from the unlocked store and encrypt
  with the backup password. Auto-backup is only ever triggered by changes in the running app, and no background
  task exists (no `BGTaskScheduler`), so nothing needs the vault while it's locked. The backup format keeps its
  own KDF and container.
- **Killphrases.** Matching and deletion happen in memory, then the file is replaced. The deleted item is gone
  from the live file at once, where today it stays in `vault-primary.sqlite` until a checkpoint.
- **Search passphrases.** Matched in memory with the same digester.
- **HMAC keys.** The killphrase and search passphrase keys stay device-wide keychain items. Per-item salts make
  sharing them across vaults harmless.
- **Rehash stores.** Only meaningful in `plain` mode. They must be empty before migrating, and they're deleted by
  it.
- **Payload hash** (`currentPayloadHash`). Unchanged; computed from the export.

## What's readable at rest

| Artifact | Today | Password on |
| --- | --- | --- |
| Vault store | Everything, plus killphrase residue until checkpoint | The header (format, slot count, slot size bucket, KDF parameters, salt). Nothing per vault. |
| Device backups (iCloud, Finder) | The plaintext store | Ciphertext, open to offline guessing of the password |
| QuickType identity store | Issuer, account and UUID per visible OTP | Empty |
| Widget timelines | Issuer, account, codes | Locked placeholder |
| Configured widget entities | Issuer, account | Unchanged until the user removes the widget (residual) |
| Pending rehash files | Plaintext phrases (old-schema upgrades) | Removed; precondition of migration |
| Failed-open archives | Plaintext copies of the vault | Removed, with confirmation |
| `UserDefaults` and keychain settings | Dates, a payload hash, auto-backup configuration, the backup key | Same. VAULT-23 moves the per-vault parts into the payload. |
| Keyboard learning from note editors | Words typed with autocorrection on | Same. Outside storage; see sub-issue 15. |

## Residual limits

1. **Offline guessing.** The password is only as strong as its entropy. With the KDF budget capped near a
   second, an attacker with the file can make, as a rough upper bound, a few guesses per second per CPU core
   and hundreds per second per GPU. A 6-digit PIN falls in about half an hour on one GPU. A random 4-word
   passphrase takes more than 10,000 GPU-years. VAULT-22 should require a real password and say why. A device-bound secret would remove
   this, at the cost of restoring to a new iPhone; it's rejected above.
2. **Multiple snapshots.** Two copies of the file from different times, for example two iCloud backups or a
   seized phone plus an older backup, show which slot's bytes changed. Combined with a coerced duress password,
   which identifies the duress vault's slot, a change in another slot shows another vault is in use. Slots the
   app can't open can't be re-randomized. Mitigations: use the duress vault now and then, or add an opt-in
   "exclude the vault from device backups", which trades against restoring from a device backup.
3. **Nested duress creation.** The real vault is guaranteed untouched for five levels at N = 8, L = 4. Beyond
   that it isn't; see [Duress vault](#duress-vault-vault-23).
4. **Slot size.** The slot size bucket reveals that some vault once exceeded the previous bucket. It starts at
   1 MiB, about 3,500 items, so this only applies to very large vaults.
5. **Fixed KDF parameters.** Raising them later needs a new format version whose unlock derives under both
   parameter sets (twice the time) during a transition, or an erase and re-create.
6. **Memory.** Decrypted items can't be reliably zeroed after locking (see above).
7. **Rollback.** Someone who can write the app's files can put back an older copy of the file. Local storage
   can't prevent this.
8. **Surfaces outside storage.** Configured widget entities, keyboard learning, and item dates inside a duress
   vault.

## Test strategy

- **KDF.** RFC 9106 Argon2id test vectors, or RFC 7914 for the fallback. Determinism, cancellation, and a
  memory-high-water check. A calibration command in `vault-keygen-speedtest`, plus a run on the oldest
  supported device before `t` is fixed.
- **Format.**
  - Round-trip every field.
  - Wrong password, wrong slot and wrong header all fail closed.
  - Flipping any single byte of the header, key box or body makes the slot fail to open.
  - Growth preserves other slots, and they still open.
  - Every slot has identical length.
  - Plaintext markers seeded into items never appear in the file bytes.
- **Semantics.**
  - The existing `PersistedLocalVaultStoreTests` become a contract suite, parameterized over the SwiftData
    store and `RecordVaultStore`.
  - A **differential test** applies seeded random operation sequences (insert, update, delete, reorder, tag
    changes, import merge and override, killphrase and search passphrase queries) to both engines and compares
    `exportVault`, `retrieve` and `retrieveTags`.
  - A schema parity test between `VaultRecord` and the latest `VersionedSchema`.
- **Crash safety and fault injection.** An injectable `SlotFileSystem` (write, `F_FULLFSYNC`, rename, remove,
  flock) with two modes:
  - **fail at step k**: the operation throws. Assert nothing changed on disk or in memory.
  - **crash at step k**: execution stops, then launch recovery runs on the resulting disk state.

  For save, password change, growth, turning the password on (migration), turning it off, making a duress vault
  and erasing, enumerate every k and assert:
  - Exactly one consistent mode.
  - Every item from before the operation readable with the right password, either in its old or new state.
  - No plaintext store left once migration has committed.
- **Migration.** SwiftData SQLite fixtures at V1, V2 and V3, as in `PersistedSchemaMigrationExecutionTests`,
  with pending rehash entries, undecodable items, and failed-open archives. Migrate, then compare record for
  record.
- **Duress and timing.**
  - Injected spies count derivations, slot trials and body opens for real, duress and wrong passwords, and they
    must be equal.
  - An injected clock checks the deadline.
  - `duressSlots` never contains the vault's own slot or the creator's, and a root-created chain never targets
    the root for L + 1 levels.
  - Password collisions resolve by recency.
- **Concurrency.** Two stores on one file in-process (standing in for the app and AutoFill): a conflicting
  write is detected, never lost.
- **Extensions.** The widget provider returns the locked state in password mode, and the QuickType store is
  never called in that mode. Snapshots for the new locked states.
- **Performance guards.** Save and load at 1,000 items inside a budget, so the numbers above don't regress.

## Consequences to accept

1. While the password is on, widgets show a locked placeholder and QuickType suggestions are gone. AutoFill
   asks for the app lock password in its sheet every time. Face ID alone can't unlock (C4).
2. A forgotten password means erasing and restoring from a backup. Setting the password should say so, and show
   the last backup date.
3. Offline guessing is bounded only by the password's strength. VAULT-22 needs a minimum strength.
4. Unlocking adds the derivation, about 0.2–0.5 s depending on the device, on top of device authentication.
5. The encrypted file is at least 8 MiB. Every change rewrites it: about 17 ms at 1,000 items on the M5 Max,
   and likely somewhat more on a phone.
6. Turning the password off keeps the encrypted file with a device-key wrap. Widgets and AutoFill come back
   only once sub-issue 11 lands.
7. The duress limits above: snapshots, nesting depth, and item dates.
8. KDF parameters are fixed when the file is created.
9. No app downgrade after the password has been set.
10. Users who never set a password are unaffected.

## Sub-issues

These are in implementation order. Each is one PR with its own tests.

1. **Make the vault store switchable at runtime.** Replace `VaultRoot`'s `static let vaultStore` with a
   `VaultStoreSession` that implements the store protocols and forwards to the plain store, an unlocked
   encrypted store, or `locked` (reads return nothing, writes throw). `VaultDataModel` purges items, tags and
   caches when it locks. No behavior change: the plain store opens at launch as today. It coordinates with
   VAULT-21's lock state. **Tests:** forwarding, locked behavior, purge. Prerequisite for VAULT-22.
2. **Introduce `VaultRecord` and share the item and tag codecs.** `PersistedVaultItemEncoder` and
   `PersistedVaultItemDecoder` (and the tag pair) produce and consume `VaultRecord`. The SwiftData store copies
   records to and from `@Model` objects. Adds the schema parity test. No behavior change. **Tests:** round
   trips, parity, and the existing suite.
3. **Add the in-memory `RecordVaultStore`.** Implements every store protocol over records. The store test suite
   becomes a contract suite run against both engines, plus the differential random-operation test. Not wired
   into the app yet.
4. **Add the app lock KDF.** The vendored Argon2id C target (or the scrypt fallback) and
   `VaultKeyDeriver.Signature.appLockV1`. Also RFC test vectors, zeroing of working memory, a calibration
   command in `vault-keygen-speedtest`, and on-device calibration before `t` is fixed. Can run in parallel with
   2 and 3.
5. **Add the slot file format.** A pure `VaultSlotFile`: header, slots, password and device-key wraps, body
   seal and open, growth, random fill, AAD binding. **Tests:** round trip, tamper, wrong password, equal slot
   lengths, no plaintext leakage.
6. **Add `EncryptedVaultStore` persistence.** `RecordVaultStore` plus the atomic, verified whole-file
   replacement, `flock` and generation conflicts, and failure handling (including killphrase returning
   `false`). **Tests:** fault injection at every step, and concurrency.
7. **Add the unlock and lock service.** Derive, try every slot, the deadline, the recency tie-break, zeroing,
   and a hook for the attempt counter. **Tests:** operation counts per path and the deadline, with an injected
   clock and the testing KDF. Part of VAULT-22.
8. **Turn on encryption: convert plain to encrypted.** The state file and journal, preconditions (rehash
   drained, archives, no load failure), verified conversion, launch recovery, and switching the session. **Tests:**
   crash at every step, and SwiftData fixture migrations. Depends on 1–7. It's what VAULT-22's setup calls, so
   it's part of VAULT-22.
9. **Change the password, turn it off (device-key wrap), turn it back on.** Journaled. Needs the current
   password (VAULT-22). **Tests:** crash at every step, and old and new password behavior. Part of VAULT-22.
10. **Lock down system surfaces while the password is on.** Empty and gate the QuickType identity store, add the
    widget locked state and empty entity query, reload timelines, and add password unlock in the AutoFill sheet,
    with a check of the extension's memory headroom and cross-process `flock`. **Tests:** plus snapshots of the
    locked states. Part of VAULT-22.
11. **Bring back widgets, AutoFill and QuickType with the device key.** A keychain access group for the
    extensions, and an extension reader for the slot file. It only matters after the password has been turned
    off, and can be deferred.
12. **Duress slots.** `duressSlots`, "make duress database" into a slot, the same-password rules, and a
    per-vault settings section (backup password and record, backup events, auto-backup configuration and
    retention). **Tests:** chain safety, payload shape equality, timing equality, auto-backup isolation. Part of
    VAULT-23, and depends on 5–9. VAULT-23 also needs its own UI issues.
13. **Erase as key destruction.** Journaled erase back to a fresh plain store. Part of VAULT-34, and depends on
    8 and VAULT-22's attempt counter.
14. **Fix: backups drop `showInQuickType` and `previewMode`.** Separate from this chain. Found while evaluating
    the backup format: a restore turns QuickType back on for opted-out items (C7) and resets note previews. Add
    both fields to `VaultBackupItem` as optional, defaulting to today's values when missing.
15. **Audit text input traits.** Separate. Note bodies and other free-text fields use autocorrection, which
    feeds the system keyboard's learned words. Decide field by field.

**Dependencies:**

- VAULT-22 depends on 1–10.
- VAULT-23's storage work is 12, and depends on VAULT-22.
- VAULT-34's storage work is 13, and depends on VAULT-22's attempt counter.
- VAULT-21 is independent, but sub-issue 1's lock state should be the one VAULT-21 introduces.

## Appendix: measurements

**Setup.** Throwaway Swift packages, not in this PR, built with `swift build -c release`. They ran on an Apple
M5 Max (macOS 27, Xcode 27) under concurrent load from other builds. Each figure is the minimum of several
runs (usually five), with medians close unless noted. No iPhone was measured. An M5-class P-core is roughly an iPhone 17 or 18 Pro;
an A15-class iPhone is estimated at about twice as slow.

**Data.** The item mix matches the app's schema: 60% TOTP, 30% notes, 10% password-encrypted items, 8 tags,
0–2 tags per item, 5% with killphrases and 3% passphrase-hidden. "Typical" notes average 800 characters;
"heavy" notes average 6,000.

### Key derivation

| KDF | Memory | Time |
| --- | ---: | ---: |
| CryptoSwift scrypt N=2¹⁴, r=8, p=1 | 16 MiB | 49 ms |
| CryptoSwift scrypt N=2¹⁶, r=8, p=1 | 64 MiB | 151–166 ms |
| CryptoSwift scrypt N=2¹⁷, r=8, p=1 | 128 MiB | 319 ms |
| Optimized scrypt N=2¹⁶, r=8, p=1 / 2 / 3 / 4 | 64 MiB | 62 / 132 / 197 / 244 ms |
| Optimized scrypt N=2¹⁷ / 2¹⁸, r=8, p=1 | 128 / 256 MiB | 124 / 257 ms |
| Argon2id m=64 MiB, t=3 / 6 / 8 (reference C, p=1) | 64 MiB | 68 / 129 / 170 ms |
| Argon2id m=128 MiB, t=1 / 3; m=256 MiB, t=1 | 128–256 MiB | 46 / 139 / 92 ms |
| CommonCrypto PBKDF2-SHA256, 1M iterations | — | 114 ms |
| App today: `Item.Secure.v1` / `Backup.Fast.v1` | — | 733 / 4 ms |
| Trying 8 slots (HKDF + AES-GCM open each) | — | 0.02 ms |

The optimized scrypt matched RFC 7914's vectors and CryptoSwift's output. A process deriving with 64 MiB peaked
at a 75 MB footprint.

### Payload sizes

| | 10 items | 100 | 1,000 | 5,000 |
| --- | ---: | ---: | ---: | ---: |
| JSON, typical | 9 KiB | 85 KiB | 874 KiB | 4.4 MiB |
| Compressed, typical | 3 KiB | 24 KiB | 278 KiB | 1.36 MiB |
| JSON / compressed, heavy notes | 35 / 10 KiB | 267 / 72 KiB | 2.5 MiB / 697 KiB | — |

### Save and load (typical profile)

| Approach | 10 items | 100 | 1,000 | 5,000 |
| --- | ---: | ---: | ---: | ---: |
| SwiftData in memory: save (snapshot → encrypt → `F_FULLFSYNC`) | 4.8 ms | 10.9 ms | 82 ms | 452 ms |
| SwiftData in memory: load (read → decrypt → rebuild → feed) | 4.1 ms | 17.9 ms | 175 ms | 1,142 ms |
| Record store: save (encode → compress → seal → 8 MiB file) | ~8 ms | ~9 ms | ~17 ms | ~85 ms |
| Record store: load (decrypt → decompress → decode → feed) | <1 ms | ~1.5 ms | ~9 ms | ~45 ms |
| Today's SQLite: update one item and save | 0.3 ms | 0.3 ms | 0.4 ms | 1.9 ms |
| Today's SQLite: open container and fetch feed | 1.1 ms | 2.1 ms | 13 ms | 62 ms |
| Search, record store / SwiftData in memory / SQLite | — | — | 2 / 4.6 / 4.7 ms | 10 / 22 / 33 ms |

Record store figures are sums of measured components.

### Other measurements

- **Writing the whole file atomically** with `F_FULLFSYNC`: 5 ms at 2 MiB, 6–7 ms at 8 MiB, 9 ms at 16 MiB.
- **Encrypting 1 MiB:** CryptoKit AES-GCM 0.1 ms, CryptoSwift AES-GCM 28 ms.
- **Compressing 1,000 typical items:** lzma (the backup's) 105 ms, zlib 9 ms, lzfse 4 ms. Decompressing: zlib
  4 ms, lzfse 0.5 ms.
- **Custom `DataStore`:** see [approach 2](#2-a-custom-swiftdata-datastore).
- **SQLite killphrase residue:** see [What's on disk today](#whats-on-disk-today).
