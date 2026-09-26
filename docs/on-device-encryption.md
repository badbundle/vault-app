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
- The design that meets every point is a **single encrypted file of sixteen equal-size slots**. It holds the
  vault as plain records, which are decoded into an in-memory record store while the vault is unlocked. There's
  a random data key per vault, wrapped by a key derived from the password with Argon2id. Every change is written
  as an atomic, verified replacement of the whole file.
- Deriving the key is calibrated to about 0.5 s on the device that creates the file. On an M5 Max, 8 passes take
  170 ms. Trying all sixteen slots takes about 0.04 ms, and loading a 1,000-item vault about 9 ms. Saving a
  change takes about 19 ms at 1,000 items and 90 ms at 5,000, including a full `F_FULLFSYNC`.
- Users who never set an app lock password keep today's SQLite store, unchanged.

What Bradley has to accept is listed under [Consequences](#consequences-to-accept). The main ones:

- While the password is on, widgets can't show codes and QuickType suggestions go away. AutoFill asks for the
  password in its own sheet.
- The password has to be a real password. Anyone who copies the file can guess offline at the speed the KDF
  allows.
- A forgotten password means restoring from a backup.
- Turning the password off keeps the encrypted file, with its key wrapped by a device key. It doesn't convert
  back to SQLite, because that can't be done without destroying the other slots. Widgets, AutoFill and
  QuickType work again once it's off.

Two limits apply to any deniable design, not just this one. They're explained in
[Residual limits](#residual-limits):

- Someone holding copies of the file from two different times can see which slot changed.
- A coercer who nests "make duress database" more than eleven levels deep eventually puts the real vault at risk.
  No finite design can prevent that without leaving a mark in the duress vault they're given.

## Decisions

Recorded after review. They supersede anything in the first draft that differs.

1. **KDF:** Argon2id, from the PHC reference C code (CC0) vendored as a C target. There's no scrypt fallback.
2. **Calibrated on the device, when the file is created.** The KDF parameters live in the file header, so they're
   chosen on the device that creates the file, not fixed in advance:
   - Memory stays at 64 MiB.
   - Passes are calibrated to target about 0.5 s, with a floor of 3 and a ceiling of 32.
   - The unlock deadline is set at the same time.
   - The file has one parameter set, so the AutoFill extension checks its memory headroom before deriving.

   See [Key derivation](#key-derivation).
3. **Slots:** N = 16 and L = 10. That's a 16 MiB file, and the real vault is safe for eleven levels of nesting.
4. **No "exclude from device backups" option** for now. It stays documented as a mitigation under
   [Residual limits](#residual-limits).
5. **Sub-issue 11 is in scope.** Turning the password off must bring widgets, AutoFill and QuickType back.
   Otherwise it would be a lasting compromise.
6. **Separate tickets**, outside this chain:
   - The backup fields: VAULT-53.
   - Keyboard learning: VAULT-54.
   - Plaintext residue in today's store (WAL, failed-open archives, rehash files): VAULT-55.
7. **Ownership:**
   - The agent doing VAULT-21's lock state does sub-issue 1 (VAULT-40) on top of VAULT-21, then the VAULT-22 UI
     and the system surfaces (VAULT-49 and VAULT-50).
   - The storage core, sub-issues 2 to 9 (VAULT-41 to VAULT-48), is one PR each, in order.
   - The duress storage (VAULT-51) and erase (VAULT-52) come later.

## Contents

1. [Decisions](#decisions)
2. [What's on disk today](#whats-on-disk-today)
3. [Approaches evaluated](#approaches-evaluated)
4. [Design](#design)
5. [Duress vault (VAULT-23)](#duress-vault-vault-23)
6. [Erasing after failed attempts (VAULT-34)](#erasing-after-failed-attempts-vault-34)
7. [Widgets, AutoFill and QuickType](#widgets-autofill-and-quicktype)
8. [Backups, killphrases and everything else](#backups-killphrases-and-everything-else)
9. [What's readable at rest](#whats-readable-at-rest)
10. [Residual limits](#residual-limits)
11. [Test strategy](#test-strategy)
12. [Consequences to accept](#consequences-to-accept)
13. [Sub-issues](#sub-issues)
14. [Appendix: measurements](#appendix-measurements)

## What's on disk today

These are facts from the code and from the prototypes described in the [appendix](#appendix-measurements).

- **The vault** is a SwiftData SQLite store, `vault-primary.sqlite` with `-wal` and `-shm`, in the App Group
  container (`VaultSharedStorage`). The app, the AutoFill extension and the widget extension all open it. Every
  field is plaintext, except the payloads of items that have their own password (`encryptedItemDetails`).
- **Deletion residue (fixed in VAULT-55).** A delete only goes to the WAL, and the system SQLite's
  `secure_delete = FAST` leaves whole freed pages (a long note's overflow pages) intact on the freelist. The
  app keeps the store open all session, and SQLite only checkpoints automatically at about 1,000 WAL pages. Since
  VAULT-55, the store runs `VACUUM` and `wal_checkpoint(TRUNCATE)` on a second connection straight after a
  deletion (killphrase, single item, delete all, override import) or a killphrase or search passphrase change,
  and again at launch if there are freed pages (`PersistedStoreScrubber`). Edits still leave the old version on
  freed pages until the next launch.
- **Device backups.** The App Group container is included in iCloud and Finder device backups, so the plaintext
  store is too. Without Advanced Data Protection, iCloud Backup is readable by Apple.
- **Readable flags.** Non-null `killphraseDigest` and `searchPassphraseDigest` columns show which items have a
  killphrase or a search passphrase to anyone who can read the file. That's the enumeration C5 forbids in the UI.
- **The QuickType identity store** (`ASCredentialIdentityStore`) holds the issuer, account name and item UUID
  of every visible OTP item, outside the app's sandbox.
- **Widgets.** WidgetKit archives the rendered timeline entries (issuer, account name, current code) in system
  storage. It also keeps the configured `OTPWidgetItemEntity`, which has the issuer and account name.
- **Pending rehash files.** `vault-primary.pending-killphrase-rehash.json` and the search passphrase equivalent
  hold plaintext phrases between a V1→V2 or V2→V3 migration and the rehash run later in the same launch. The run
  deletes them once every entry is applied, or straight away if they can't be decoded; a crash mid-drain leaves
  them for the next launch's run. Deleting all data deletes them too.
- **Failed-open archives.** When the store can't be opened, `PersistedLocalVaultStoreFactory` moves it into
  `vault-primary.failed-open-<timestamp>/`. Those are full plaintext copies of the vault. Nothing reads them
  again, but they may hold the only copy of some items, so they're never deleted automatically. Since VAULT-55
  the Backups page says a vault was set aside and offers to delete it, and deleting all data deletes them.
- **Backup PDFs.** A PDF backup is the whole vault, encrypted with the backup password, including items deleted
  since it was made. Until VAULT-62, each one stayed in the app's `tmp/` until the system cleared it. Now the file
  only exists while the share sheet has it (`BackupPDFTemporaryFiles`), and any left behind, if the app was closed
  with the sheet open, are deleted when the Backups page next opens.
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

The same whole-file approach, but the unlocked vault is held as plain `VaultItemRecord` values, a field-for-field
mirror of the persisted schema, in an actor that implements the existing store protocols. No SwiftData is
involved.

- **Loading a 1,000-item vault takes about 9 ms**: decompressing 0.5 ms, decoding 5.7 ms, and filtering and
  sorting the feed 2.5 ms. At 5,000 items it takes about 45 ms.
- **Saving takes about 19 ms at 1,000 items**: encoding, compressing, sealing and replacing the whole 16 MiB file
  with `F_FULLFSYNC`. At 5,000 items it takes about 90 ms.
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
    opted out, which C7 cares about. That's now VAULT-53.
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
  password set     →  │ vault-slots.v1   header │ slot 0 │ slot 1 │ … │ slot 15   │
                      │ vault-slots.lock  (flock, empty)                         │
                      │ vault-storage-state.json  (mode + transition journal)    │
                      └──────────────────────────────────────────────────────────┘

  unlock:  password ──Argon2id(salt)──► K_pw ──HKDF(slot nonce)──► W_i ──open──► data key K
           K ──open body──► lzfse ──► JSON ──► [VaultItemRecord] ──► RecordVaultStore (in memory)
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
  restores it with the file. Its accessibility class is set in sub-issue 11 to whatever widgets need to keep
  working as they do today.
- `K_i`, the data key, is 256 random bits per vault. It's sealed under `W_i` together with the body length, a
  generation counter and the time it was wrapped.
- The body is sealed under `K_i` with AES-256-GCM (CryptoKit) and a fresh nonce on every save.

**Changing the password** derives the new `K_pw`, reseals `K_i` under the new `W_i` and rewrites the file. The
body is untouched. Every save re-encrypts the body anyway, because the whole vault is a few hundred KiB.

The salt and KDF parameters are **shared by all slots** and fixed for the life of the file. That lets one
derivation test every slot. It also means the parameters can't be raised later for vaults the app can't open
(see [Residual limits](#residual-limits)).

### Key derivation

**Argon2id, m = 64 MiB, p = 1, with the number of passes `t` calibrated on the device that creates the file.**
It comes from the PHC reference implementation, vendored unmodified as the `CArgon2` target (CC0 or Apache-2.0,
about 3,800 lines, no warnings). It's compiled with `-O3` in every configuration: with Xcode's default `-Os`, a
pass took about 1.7 times as long on the M5 Max, which would buy that much less attacker cost in the same half
second.

**Calibration.** The parameters live in the file header, so they're chosen when the file is created: at the
first conversion (sub-issue 8), and again after an erase if a password is set anew. On that device:

1. Run Argon2id with m = 64 MiB and t = 3 on a throwaway password and salt, three times. Take the fastest run,
   so a busy moment can't make the choice too cheap. The time per pass is that run's time divided by 3.
2. Choose `t` = clamp(⌊0.5 s ÷ time per pass⌋, 3, 32).
   - The floor, 3 passes at 64 MiB, is RFC 9106's recommended profile for memory-constrained environments.
   - The ceiling bounds unlock time if the file is later restored onto a slower iPhone, or if a much faster
     device calibrates.
   - At the M5 Max's roughly 21 ms per pass, this picks about 24 passes.
3. Set the unlock deadline to 1.5 × `t` × the time per pass. That leaves about 0.25 s at the target for trying
   the slots and decoding the vault (about 45 ms at 5,000 items). The deadline is device-local and kept in the
   storage state file, not the header. If a derivation ever takes longer than the deadline, for example after a
   restore onto a slower phone, the deadline is raised to 1.5 × the observed time. It never goes down. Real,
   duress and wrong passwords derive identically, so this adjustment reveals nothing.
4. Write m, `t` and p into the header. Every slot in the file uses them for the life of the file.

Calibration adds about 0.3–1.5 s, once, to setting the password. It runs behind the setup flow's progress state.

**Memory and the AutoFill extension.**

- m is fixed at 64 MiB, not calibrated. Bitwarden warns about iOS AutoFill only above 64 MiB of Argon2id memory
  ([Bitwarden: KDF algorithms](https://bitwarden.com/help/kdf-algorithms/)). A CLI process deriving with 64 MiB
  peaked at a 75 MB footprint.
- The file has one parameter set, and the extension's limit can't be measured from the app that creates the file.
  So before deriving, the AutoFill extension checks `os_proc_available_memory()` against m plus a margin (16 MiB).
  If there isn't enough headroom, the sheet tells the user to open Vault instead of risking a crash. The app can
  always unlock.
- It derives before building any vault UI, and releases the working memory straight after.
- The unlock service (sub-issue 7) exposes the check. Sub-issue 10 uses it.

**Why Argon2id.**

- Measured on the M5 Max, Argon2id fills 64 MiB three times in 68 ms.
- As a rough memory-bandwidth bound, one guess at 8 passes moves about 1.5 GiB. That's about four times what
  scrypt N = 2¹⁶, r = 8, p = 3 (about 384 MiB) moves in about the same time (197 ms). Argon2id also resists
  time–memory trade-offs better.
- A GPU guessing at 8 passes is bandwidth-bound at roughly 650 guesses per second per TB/s. At the calibrated
  ~0.5 s it's proportionally fewer. That's a rough upper bound, not a measurement.

**API.** It's a new `Argon2idKeyDeriver` in `CryptoEngine`, parameterized by the header. It isn't a fixed
`VaultKeyDeriver.Signature`, because its parameters differ from file to file.

For comparison, the existing per-item password KDF (`Item.Secure.v1`) takes 733 ms on the M5 Max. The backup's
`Secure.v1` spends about 13 s on PBKDF2 alone there, and minutes on an iPhone.

### On-disk format (`vault-slots.v1`)

One file: a 128-byte plaintext header followed by `slotCount` slots of `slotSize` bytes each.

```
Header (plaintext; same layout on every install, only the salt differs)
  0   8  magic "VLTSLOTS"
  8   2  format version = 1
  10  2  slot count = 16
  12  4  slot size in bytes (1 MiB × 2^k)
  16  2  KDF id (1 = Argon2id)
  18  4  Argon2 memory KiB (65,536)   22 4  Argon2 passes t (calibrated, 3–32)   26 1  Argon2 lanes (1)
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

Integers are big-endian. In the AAD, `header` is the 128 header bytes with the slot size zeroed, because growth
changes it for slots the app can't open, and `i` is 2 bytes. It's `VaultSlotFile` in `VaultFeed` (VAULT-44).

- **Versioning.** A reader checks the magic, then the version, and refuses any version it doesn't know before
  reading anything else, so a newer layout is never misread. A change to the header or slot layout gets a new
  version, and can use the reserved bytes. Version 1 requires them, and the gap after the lanes, to be zero.
  Changes to the payload don't need one: the body records its payload version and compression (0 = none,
  1 = lzfse).
- **Header limits.** Before deriving anything, a reader refuses Argon2id parameters outside 8 KiB–1 GiB of memory,
  1–32 passes and 1–8 lanes, and a slot size that isn't 1 MiB × 2^k up to 64 MiB or doesn't match the file's
  length. A changed header can't make unlocking run for hours or ask for gigabytes.
- **Generations and wrap times.** Every write to a slot increments its generation: creating it, saving and
  rewrapping. A write is refused if the slot's current key box doesn't open at the generation the writer loaded.
  The wrapped-at time is set when a vault is created or rewrapped, and saves keep it.
- **Rewrapping** (password change, or switching between the password and the device key) reseals the key box
  only. The slot nonce and body stay as they are.
- **Unused slots** are random bytes. AES-GCM output is indistinguishable from random, so an empty slot, a real
  vault and a duress vault look the same.
- **The header is authenticated** as AAD, so tampering with the KDF parameters or the salt makes every slot fail
  closed. The slot size is left out because growth changes it. A changed slot size fails the length and layout
  checks instead.
- **Padding.** Each vault writes its body to fill its slot, so a slot's contents reveal nothing about its size.
- **Slot size** starts at 1 MiB, which holds about 3,500 typical items or 1,400 heavy-note items once
  compressed. It doubles when any vault outgrows it, up to 64 MiB; a payload too large for that is refused. On
  growth, the vault being written re-seals its own slot at the new size, and every other slot is copied byte for
  byte with random fill appended. Their key box carries their real body length, so they still open. Slots never
  shrink, because the app can't know what the others hold.
- **Total size** is 16 MiB at the minimum (16 slots of 1 MiB). Rewriting it takes 9 ms on the M5 Max. After a
  growth to 2 MiB slots it's 32 MiB.
- **File protection** is `.complete` in password mode: only the foreground app and the AutoFill sheet read it,
  and both run while the device is unlocked. In `encrypted(deviceKey)` mode, use the same class as today's
  store, so widgets behave as they do now ([sub-issue 11](#sub-issues)).
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
  "items": [VaultItemRecord],   // every PersistedSchemaV3.PersistedVaultItem field + details, raw strings
  "tags":  [VaultTagRecord],
  "vault": { "duressSlots": [UInt8] /* VAULT-23 */, "settings": { /* per-vault settings, VAULT-23 */ } } }
```

- **`VaultItemRecord` mirrors the persisted schema, not the domain model.** Migration is then a field-for-field
  copy that can't fail, and an item that fails domain decoding in SQLite today survives the migration byte for
  byte.
- **One encoder and one decoder.** `PersistedVaultItemEncoder` and `PersistedVaultItemDecoder` are refactored to
  produce and consume `VaultItemRecord`. The SwiftData store copies records to and from `@Model` objects.
- **Payload version.** Each version adds optional fields with defaults, and the decoder accepts every older
  version. SwiftData schema migrations don't apply to encrypted vaults.
- **A schema parity test** fails if the latest `VersionedSchema` has an attribute that `VaultItemRecord` doesn't
  carry. Forgetting a field would otherwise silently drop data at migration.

### Reading and writing while unlocked

`RecordVaultStore` is an actor. It implements `VaultStoreReader`, `VaultStoreWriter`, `VaultStoreReorderable`,
`VaultStoreExporter`, `VaultStoreImporter`, `VaultStoreDeleter`, `VaultStoreKillphraseDeleter`,
`VaultStoreHOTPIncrementer` and `VaultTagStore` over `[VaultItemRecord]` and `[VaultTagRecord]`, keyed by id.
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
2. Snapshot the SQLite store to `[VaultItemRecord]`.
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
2. Start the device's fixed unlock deadline, set during calibration (see [Key derivation](#key-derivation)).
3. Derive `K_pw` off the main actor.
4. Try **every** slot's key box, with no early exit.
5. If exactly one opens, open its body. If more than one opens, pick the most recently wrapped (see
   [same passwords](#same-passwords)). Decode it.
6. Drop `K_pw` and every `W_i`. They're CryptoKit `SymmetricKey`s, whose storage is zeroed on release. The
   Argon2 working memory is `memset_s`'d before it's freed.
7. Wait for the deadline. Then reset the counter and show the vault, or show the error.

Wrong, real and duress passwords all run the same derivation and the same sixteen trials, and finish at the same
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

- **Sixteen slots always exist.** A file with a duress vault looks exactly like one without.
- **Unlock timing is identical,** as described above.
- **Each vault is a full payload,** with its own items, tags, killphrases and per-vault settings: backup
  password, backup events, auto-backup configuration and the "backup password is set" record. VAULT-23 moves
  those from `UserDefaults` and the keychain into `payload.vault.settings`.

### Making a duress database, from any vault

Each vault's payload carries `duressSlots`, a list of L = 10 distinct slot indices that never includes its own.
The first vault, created at migration, gets ten random slots ≠ `r`.

"Make duress database" from vault V, with a new password:

1. Target = `V.duressSlots[0]`, always the same slot. So making another duress vault replaces V's previous one,
   as VAULT-23 decided.
2. Create W in the target slot: an empty payload and a new data key, wrapped with the new password (same salt).
3. `W.duressSlots = V.duressSlots[1...] + [x]`, where x is random from the slots not in
   {V's slot, W's slot} ∪ `V.duressSlots[1...]`.
4. Replace the file, as for any save. V keeps working with its password.

From inside a duress vault, this behaves exactly as it does from the real vault: same steps, same timing, same
payload shape. A payload shows only "ten other slots", which is true of every vault.

**The real vault is never touched for eleven levels of nesting.** Every entry the real vault writes excludes
its own slot, so a chain R → D1 → … → D11 never targets R. That's L + 1 levels at N = 16, L = 10.

From the twelfth level, an entry chosen by a duress vault, which can't know where R is, may name R's slot. The
chance is at most 1/(N − L − 1) = 1/5 per creation.

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
| Widgets | As today | Locked placeholder. `OTPWidgetItemEntityQuery` returns nothing. `reloadAllTimelines()` when the password is turned on, so archived timelines with codes are replaced. | As today: the extension reads the slot file with the device key ([sub-issue 11](#sub-issues)) |
| Widget HOTP increment | As today | Unavailable | As today (sub-issue 11) |
| AutoFill sheet (`prepareOneTimeCodeCredentialList`) | As today | Asks for the app lock password in the sheet. Checks memory headroom, derives with 64 MiB, opens the slot. Writes (HOTP) go through the same `flock` and generation check. Never Face ID alone (C4). | As today (sub-issue 11) |
| QuickType (`provideCredentialWithoutUserInteraction`) | As today | Identity store emptied when the password is turned on, and never written while it's on. Requests return `userInteractionRequired`. | Identity store synced again from the open vault when the password is turned off (sub-issue 11) |

Residual: a configured widget's saved `OTPWidgetItemEntity` (issuer, account name) sits in the system's widget
configuration, which the app can't edit. Turning on the password should tell users to remove existing widgets.

## Backups, killphrases and everything else

- **Backups, exports, device transfer, auto-backup.** Unchanged. They export from the unlocked store and encrypt
  with the backup password. Auto-backup is only ever triggered by changes in the running app, and no background
  task exists (no `BGTaskScheduler`), so nothing needs the vault while it's locked. The backup format keeps its
  own KDF and container.
- **Killphrases.** Matching and deletion happen in memory, then the file is replaced. The deleted item is gone
  from the live file at once, as it is from the SQLite store's files since VAULT-55 scrubs them after the
  delete.
- **Search passphrases.** Matched in memory with the same digester.
- **HMAC keys.** The killphrase and search passphrase keys stay device-wide keychain items. Per-item salts make
  sharing them across vaults harmless.
- **Rehash stores.** Only meaningful in `plain` mode. They must be empty before migrating, and they're deleted by
  it.
- **Payload hash** (`currentPayloadHash`). Unchanged; computed from the export.

## What's readable at rest

| Artifact | Today | Password on |
| --- | --- | --- |
| Vault store | Everything, plus old versions of edited items until the next launch | The header (format, slot count, slot size bucket, KDF parameters, salt). Nothing per vault. |
| Device backups (iCloud, Finder) | The plaintext store | Ciphertext, open to offline guessing of the password |
| QuickType identity store | Issuer, account and UUID per visible OTP | Empty |
| Widget timelines | Issuer, account, codes | Locked placeholder |
| Configured widget entities | Issuer, account | Unchanged until the user removes the widget (residual) |
| Pending rehash files | Plaintext phrases (old-schema upgrades) | Removed; precondition of migration |
| Failed-open archives | Plaintext copies of the vault | Removed, with confirmation |
| `UserDefaults` and keychain settings | Dates, a payload hash, auto-backup configuration, the backup key | Same. VAULT-23 moves the per-vault parts into the payload. |
| Keyboard learning from note editors | Words typed with autocorrection on | Same. Outside storage; separate ticket VAULT-54. |

## Residual limits

1. **Offline guessing.** The password is only as strong as its entropy. With derivation calibrated to about
   0.5 s, an attacker with the file can make, as a rough upper bound, a few guesses per second per CPU core and
   hundreds per second per GPU. A 6-digit PIN falls in about half an hour on one GPU. A random 4-word passphrase
   takes more than 10,000 GPU-years. VAULT-22 should require a real password and say why. A device-bound secret
   would remove this, at the cost of restoring to a new iPhone; it's rejected above.
2. **Multiple snapshots.** Two copies of the file from different times, for example two iCloud backups or a
   seized phone plus an older backup, show which slot's bytes changed. Combined with a coerced duress password,
   which identifies the duress vault's slot, a change in another slot shows another vault is in use. Slots the
   app can't open can't be re-randomized.

   Mitigations:
   - Use the duress vault now and then.
   - An opt-in "exclude the vault from device backups". It isn't offered for now, and it trades against
     restoring from a device backup.
3. **Nested duress creation.** The real vault is guaranteed untouched for eleven levels at N = 16, L = 10. Beyond
   that it isn't; see [Duress vault](#duress-vault-vault-23).
4. **Slot size.** The slot size bucket reveals that some vault once exceeded the previous bucket. It starts at
   1 MiB, about 3,500 items, so this only applies to very large vaults.
5. **Fixed KDF parameters.** They're calibrated once, on the device that creates the file.
   - Raising them later needs a new format version whose unlock derives under both parameter sets (twice the
     time) during a transition, or an erase and re-create.
   - Restoring the file onto a slower iPhone makes unlocking proportionally slower. The 32-pass ceiling bounds
     it.
6. **Memory.** Decrypted items can't be reliably zeroed after locking (see above).
7. **Rollback.** Someone who can write the app's files can put back an older copy of the file. Local storage
   can't prevent this.
8. **Surfaces outside storage.** Configured widget entities, keyboard learning, and item dates inside a duress
   vault.

## Test strategy

- **KDF.** RFC 9106 Argon2id test vectors and the reference repository's known-answer tests. Determinism,
  cancellation, zeroing of working memory, and a memory high-water check.
- **Calibration**, with an injected timer:
  - Floor and ceiling clamping.
  - The fastest of three runs is used.
  - The deadline is computed and only ever raised.
  - The header carries exactly the chosen parameters.
  - A file created with one set of parameters opens on a "device" that would have calibrated differently.
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
  - A schema parity test between `VaultItemRecord` and the latest `VersionedSchema`.
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
- **Extensions.**
  - The widget provider returns the locked state in password mode, and the QuickType store is never called in
    that mode.
  - In device-key mode, the extensions read the slot file and QuickType is synced again.
  - The AutoFill headroom check refuses to derive when available memory is short.
  - Snapshots for the new locked states.
- **Performance guards.** Save and load at 1,000 items inside a budget, so the numbers above don't regress.

## Consequences to accept

1. While the password is on, widgets show a locked placeholder and QuickType suggestions are gone. AutoFill
   asks for the app lock password in its sheet every time. Face ID alone can't unlock (C4).
2. A forgotten password means erasing and restoring from a backup. Setting the password should say so, and show
   the last backup date.
3. Offline guessing is bounded only by the password's strength. VAULT-22 needs a minimum strength.
4. Unlocking adds the derivation, calibrated to about 0.5 s on the device that set the password, and finishes at
   a fixed deadline of about 0.75 s. That's on top of device authentication.
5. The encrypted file is at least 16 MiB. Every change rewrites it: about 19 ms at 1,000 items on the M5 Max,
   and likely somewhat more on a phone.
6. Turning the password off keeps the encrypted file with a device-key wrap. Widgets, AutoFill and QuickType
   work again as they do today (sub-issue 11).
7. The duress limits above: snapshots, nesting depth, and item dates.
8. KDF parameters are fixed when the file is created. A restore onto a slower iPhone unlocks proportionally
   slower.
9. No app downgrade after the password has been set.
10. Users who never set a password are unaffected.

## Sub-issues

These are in implementation order. Each is one PR with its own tests. Keys and owners are from the
[Decisions](#decisions).

1. **VAULT-40: Make the vault store switchable at runtime.** Lock agent, on top of VAULT-21.
   - Replace `VaultRoot`'s `static let vaultStore` with a `VaultStoreSession` that implements the store protocols
     and forwards to the plain store, an unlocked encrypted store, or `locked` (reads return nothing, writes
     throw).
   - `VaultDataModel` purges items, tags and caches when it locks.
   - No behavior change: the plain store opens at launch as today.
   - **Tests:** forwarding, locked behavior, purge. Prerequisite for VAULT-22.
2. **VAULT-41: Introduce `VaultItemRecord` and share the item and tag codecs.** Storage core.
   - `PersistedVaultItemEncoder` and `PersistedVaultItemDecoder` (and the tag pair) produce and consume
     `VaultItemRecord`. The SwiftData store copies records to and from `@Model` objects.
   - Adds the schema parity test. No behavior change.
   - **Tests:** round trips, parity, and the existing suite.
3. **VAULT-42: Add the in-memory `RecordVaultStore`.** Storage core.
   - Implements every store protocol over records.
   - The store test suite becomes a contract suite run against both engines, plus the differential
     random-operation test.
   - Not wired into the app yet.
4. **VAULT-43: Add the Argon2id KDF with on-device calibration.** Storage core.
   - The vendored PHC reference C target and an `Argon2idKeyDeriver` parameterized by the header.
   - The calibration routine (fastest of three t = 3 runs, `t` clamped to 3–32 for about 0.5 s, and the
     deadline) behind an injectable timer.
   - Zeroing of working memory.
   - **Tests:** RFC 9106 vectors and the reference known-answer tests.
5. **VAULT-44: Add the slot file format.** Storage core.
   - A pure `VaultSlotFile` with 16 slots: header, password and device-key wraps, body seal and open, growth,
     random fill, AAD binding.
   - **Tests:** round trip, tamper, wrong password, equal slot lengths, no plaintext leakage.
6. **VAULT-45: Add `EncryptedVaultStore` persistence.** Storage core.
   - `RecordVaultStore` plus the atomic, verified whole-file replacement, and `flock` and generation conflicts.
   - Failure handling, including killphrase deletion returning `false`.
   - **Tests:** fault injection at every step, and concurrency.
7. **VAULT-46: Add the unlock and lock service.** Storage core.
   - Derive, try every slot, hold to the deadline (raised if a derivation ever exceeds it), and break ties by
     recency.
   - Zeroing, a hook for the attempt counter, and the AutoFill memory headroom check.
   - **Tests:** operation counts per path and the deadline, with an injected clock and the testing KDF.
8. **VAULT-47: Turn on encryption: convert plain to encrypted.** Storage core.
   - Calibration at file creation, and the state file and journal.
   - Preconditions: rehash files drained, archives handled, no load failure.
   - Verified conversion, launch recovery, and switching the session.
   - **Tests:** crash at every step, and SwiftData fixture migrations. Depends on VAULT-40 and 2–7. It's what
     VAULT-22's setup calls.
9. **VAULT-48: Change the password, turn it off (device-key wrap), turn it back on.** Storage core.
   - Journaled, and needs the current password (VAULT-22).
   - **Tests:** crash at every step, and old and new password behavior.
10. **VAULT-49: Lock down system surfaces while the password is on.** Lock agent.
    - Empty and gate the QuickType identity store.
    - Add the widget locked state and empty entity query, and reload timelines.
    - Add password unlock in the AutoFill sheet, with the headroom check and cross-process `flock`.
    - **Tests:** plus snapshots of the locked states.
11. **VAULT-50: Bring back widgets, AutoFill and QuickType with the device key.** Lock agent. In scope.
    - A keychain access group for the extensions and an extension reader for the slot file.
    - QuickType identities are re-synced from the open vault when the password is turned off.
12. **VAULT-51: Duress slots.** VAULT-23's storage part.
    - `duressSlots` (L = 10), "make duress database" into a slot, and the same-password rules.
    - A per-vault settings section: backup password and its record, backup events, auto-backup configuration
      and retention.
    - **Tests:** chain safety, payload shape equality, timing equality, auto-backup isolation. Depends on 5–9.
      VAULT-23 also needs its own UI issues.
13. **VAULT-52: Erase as key destruction.** VAULT-34's storage part.
    - A journaled erase back to a fresh plain store.
    - Depends on 8 and VAULT-22's attempt counter.

Separate tickets, outside this chain:

- **VAULT-53: backups drop `showInQuickType` and `previewMode`.** A restore turns QuickType back on for
  opted-out items (C7) and resets note previews.
- **VAULT-54: keyboard learning in free-text fields.** Note bodies and similar fields use autocorrection, which
  feeds the system keyboard's learned words.
- **VAULT-55: plaintext residue in today's plain store.** Killphrased items stay in the SQLite file until a WAL
  checkpoint, and failed-open archives and the pending rehash files hold plaintext.

**Dependencies:**

- VAULT-22 depends on 1–11 (VAULT-40 to VAULT-50).
- VAULT-23's storage work is VAULT-51, and depends on VAULT-22.
- VAULT-34's storage work is VAULT-52, and depends on VAULT-22's attempt counter.
- VAULT-40 builds on VAULT-21's lock state.

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
| Trying 8 slots (HKDF + AES-GCM open each); 16 slots scale linearly to about 0.04 ms | — | 0.02 ms |

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
| Record store: save (encode → compress → seal → 16 MiB file) | ~10 ms | ~11 ms | ~19 ms | ~90 ms |
| Record store: load (decrypt → decompress → decode → feed) | <1 ms | ~1.5 ms | ~9 ms | ~45 ms |
| Today's SQLite: update one item and save | 0.3 ms | 0.3 ms | 0.4 ms | 1.9 ms |
| Today's SQLite: open container and fetch feed | 1.1 ms | 2.1 ms | 13 ms | 62 ms |
| Search, record store / SwiftData in memory / SQLite | — | — | 2 / 4.6 / 4.7 ms | 10 / 22 / 33 ms |

Record store figures are sums of measured components.

### Other measurements

- **Writing the whole file atomically** with `F_FULLFSYNC`: 5 ms at 2 MiB, 6–7 ms at 8 MiB, 9 ms at 16 MiB (16
  slots of 1 MiB, the minimum).
- **Encrypting 1 MiB:** CryptoKit AES-GCM 0.1 ms, CryptoSwift AES-GCM 28 ms.
- **Compressing 1,000 typical items:** lzma (the backup's) 105 ms, zlib 9 ms, lzfse 4 ms. Decompressing: zlib
  4 ms, lzfse 0.5 ms.
- **Custom `DataStore`:** see [approach 2](#2-a-custom-swiftdata-datastore).
- **SQLite killphrase residue:** see [What's on disk today](#whats-on-disk-today).
