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
  - It padded by a random amount rather than to a fixed size. Saved backups now pad to one (VAULT-75, see
    [Backups, killphrases and everything else](#backups-killphrases-and-everything-else)).
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

The mode lives in `vault-storage-state.json` (`VaultStorageState`, VAULT-47), written atomically with
`F_FULLFSYNC`, together with the journal for in-progress transitions and the device's unlock deadline. It isn't
secret: the lock screen already shows whether a password is set.

- **No file means `plain`**, so a device that never set a password has none, and going back to `plain` removes it.
- **It's readable once the device has been unlocked after starting up**, like the plain store, so the widgets can
  tell the vault is encrypted while the device is locked.
- **Only the app recovers** from a transition a crash interrupted, at launch, before it opens any store. The
  AutoFill and widget extensions only read the state. Anything but a settled `plain`, including a file they can't
  read, counts as encrypted, so they never open the plain store then: the AutoFill extension's store session
  starts locked, and the widget loader returns nothing. An extension can live through a conversion, so it checks
  the state on every call, not just at launch (`GuardedPlainVaultStore`). (What they show is VAULT-49's.)

`plain` exists so that users who never opt in carry no new risk. The first time the password is set, there's a
one-time, verified conversion. After that, turning the password on and off only rekeys the open vault's slot.

### Key hierarchy

- `K_pw` = Argon2id(password, `salt`, params from the header): 32 bytes, derived once per unlock attempt.
- `W_i` = HKDF-SHA256(ikm `K_pw`, salt `slotNonce_i`, info `"vault.slot.wrap.password.v1"`) for each slot `i`.
  In `encrypted(deviceKey)` mode it's HKDF-SHA256(ikm `D`, salt `slotNonce_i`,
  info `"vault.slot.wrap.device.v1"`), where `D` is a 256-bit keychain item (`VaultDeviceKeychainStore`):
  - **Readable after the first unlock** (`kSecAttrAccessibleAfterFirstUnlock`), like the plain store's files, so
    the widgets can refresh while the device is locked, as they do today (VAULT-50). A stricter class would break
    that, and a looser one adds nothing they need.
  - **Migratable**, not `ThisDeviceOnly`, so a device backup restores it with the file. It never syncs to iCloud
    Keychain.
  - **In the App Group's access group**, like the attempt counter, for the extensions (VAULT-50).
  - **New every time the password is turned off**, and deleted when it's turned back on, so it only ever opens
    copies of the file written while the password was off.
- `K_i`, the data key, is 256 random bits per vault. It's sealed under `W_i` together with the body length, a
  generation counter and the time it was wrapped.
- The body is sealed under `K_i` with AES-256-GCM (CryptoKit) and a fresh nonce on every save.

**Changing the password**, turning it off and turning it back on all **rekey** the open vault's slot: a new random
`K_i`, the body sealed again under it, and the key box sealed under the new `W_i`, in one verified rename. The
old `K_i` is never written again. So the old password, with a copy of the file from before (a backup, say), reads
nothing written since, and neither box of an old copy can be spliced into the new file to open it (MANIFESTO C6).
The whole vault is a few hundred KiB, so resealing the body costs no more than a save.

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
- The unlock service (sub-issue 7) exposes the check, `hasMemoryHeadroomToUnlock()`: m, plus the file, which is
  read before deriving, plus the margin. It reads only the file's header and size. Sub-issue 10 uses it. On an
  iPhone, `os_proc_available_memory()` returning 0 means the process is already over its limit, so the check
  fails. The simulator has no limit, and the check passes there.
- **Opening the vault** after the derivation holds the file, the decompressed JSON and the decoded records. The
  derivation's 64 MiB is freed by then, and for any vault a slot can hold that's less than m plus the file, so
  the check above covers it.
- **Writes need memory too.** A HOTP counter write from the sheet replaces the whole file. At its peak a save
  holds:
  - the file twice: the new file, and the copy read back to verify it;
  - the JSON twice: encoded for the save, and decompressed again to verify it;
  - the records twice: the vault in memory, and the copy verification decodes. They take about as much memory as
    their JSON.

  That's about 36 MiB for 1,000 typical items at the minimum size, and around 180 MiB for a full 4 MiB slot. So
  before writing, the extension checks `os_proc_available_memory()` against twice the file's size plus four
  times the JSON's plus the same margin, and otherwise asks the user to open Vault (VAULT-49). Mapping the file
  instead of reading it wouldn't help: slot writes modify the bytes, and writing to a mapped `Data` crashes.

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
  1–32 passes and 1–8 lanes, and a slot size that isn't 1 MiB × 2^k up to 4 MiB or doesn't match the file's
  length. A changed header can't make unlocking run for hours or ask for gigabytes.
- **Generations and wrap times.** Creating a vault starts its generation at a random value between 1 and 2³² − 1,
  so a new vault's doesn't show how new it is, and every save and rekey increments it. A write is refused if the
  slot's current key box doesn't open at the generation the writer loaded. The wrapped-at time is set when a vault
  is created or rekeyed, and saves keep it. It's stamped by `VaultWrapStamping`, not read straight from the clock
  (see [Same passwords](#same-passwords)).
- **Rekeying** (password change, or switching between the password and the device key) gives the slot a new
  `K_i`, and seals both its boxes again. Only the slot nonce stays. The save that replaces the file checks the old
  key box no longer opens.
- **Unused slots** are random bytes. AES-GCM output is indistinguishable from random, so an empty slot, a real
  vault and a duress vault look the same.
- **The header is authenticated** as AAD, so tampering with the KDF parameters or the salt makes every slot fail
  closed. The slot size is left out because growth changes it. A changed slot size fails the length and layout
  checks instead.
- **Padding.** Each vault writes its body to fill its slot, so a slot's contents reveal nothing about its size.
- **Slot size** starts at 1 MiB, which holds about 3,500 typical items or 1,400 heavy-note items once
  compressed. It doubles when any vault outgrows it, up to 4 MiB (about 14,000 typical items, and a 64 MiB file);
  a payload too large for that is refused, as is one over 64 MiB before compression (opening stops decompressing
  past that too). The ceiling bounds memory as well as the file (see
  [Memory and the AutoFill extension](#key-derivation)). On growth, the vault being written re-seals its own slot
  at the new size, and every other slot is copied byte for byte with random fill appended. Their key box carries
  their real body length, so they still open. Each re-seals at the full size the next time it saves. Slots never
  shrink, because the app can't know what the others hold.
- **Total size** is 16 MiB at the minimum (16 slots of 1 MiB). Rewriting it takes 9 ms on the M5 Max. After a
  growth to 2 MiB slots it's 32 MiB.
- **File protection** is `.complete` in password mode: only the foreground app and the AutoFill sheet read it,
  and both run while the device is unlocked. In `encrypted(deviceKey)` mode it's the same class as today's store,
  `.completeUntilFirstUserAuthentication`, so widgets behave as they do now
  ([sub-issue 11](#sub-issues)). Each rekey sets the class for the mode it moves to
  (`EncryptedVaultFile.protection(for:)`), and saves keep it.
- **Device backups** keep including the file. It's ciphertext, and it's portable: the password plus the file
  are enough to restore on a new iPhone.

### Payload

JSON, with data as base64, compressed with lzfse. The body header records the payload version and the
compression, so either can change later. It's `EncryptedVaultPayload` (VAULT-45).

- **Dates** use `Date`'s own encoding, seconds since 2001 as a JSON number, which reads back exactly.
  Milliseconds since 1970, as first planned, rounded about half of all dates, so a vault read back wouldn't equal
  the one saved, and verifying a save would fail.
- lzfse decompresses fastest, which is what unlocking waits on: 0.5 ms at 1,000 items and 3 ms at 5,000,
  against 4 ms and 21 ms for zlib.
- Compress with the Compression framework's streaming API. `NSData`'s one-shot lzfse took 155 ms to compress
  the 4.4 MiB payload at 5,000 items, against 49 ms for zlib.

```
{ "items": [VaultItemRecord],   // every PersistedSchemaV3.PersistedVaultItem field + details, raw strings
  "tags":  [VaultTagRecord],
  "vault": { "duressSlots": [UInt8] /* VAULT-51 */, "settings": VaultBackupSettings /* VAULT-70 */ } }
```

The keys are the records' property names. The version is the body header's, not a JSON field. `vault` arrives
with VAULT-51, and its `settings` with VAULT-70 (see
[Each vault's backup settings](#each-vaults-backup-settings-vault-70)). `settings` is always written, with every
key, `null` when it's unset, so every vault's payload has the same sections whatever it holds.

- **`VaultItemRecord` mirrors the persisted schema, not the domain model.** Migration is then a field-for-field
  copy that can't fail, and an item that fails domain decoding in SQLite today survives the migration byte for
  byte.
- **One encoder and one decoder.** `PersistedVaultItemEncoder` and `PersistedVaultItemDecoder` are refactored to
  produce and consume `VaultItemRecord`. The SwiftData store copies records to and from `@Model` objects.
- **Payload version.** Each version adds optional fields with defaults, and the decoder accepts every older
  version. A version newer than the app knows is refused rather than read, because saving it would drop what the
  newer app added. SwiftData schema migrations don't apply to encrypted vaults.
- **A schema parity test** fails if the latest `VersionedSchema` has an attribute that `VaultItemRecord` doesn't
  carry. Forgetting a field would otherwise silently drop data at migration.

### Reading and writing while unlocked

`RecordVaultStore` is an actor. It implements `VaultStoreReader`, `VaultStoreWriter`, `VaultStoreReorderable`,
`VaultStoreExporter`, `VaultStoreImporter`, `VaultStoreDeleter`, `VaultStoreKillphraseDeleter`,
`VaultStoreHOTPIncrementer` and `VaultTagStore` over `[VaultItemRecord]` and `[VaultTagRecord]`, keyed by id.
`EncryptedVaultStore` wraps it with the slot file. Mutations take turns, and each one:

1. Computes the new records from the current ones, without publishing them. If nothing changed, it stops there.
2. Takes `flock(LOCK_EX)` on `vault-slots.lock` and reads the current file. If our slot's generation isn't the
   one we loaded, another process has written it: it stops with a conflict and reloads, then works the mutation
   out again on top of what the other process saved and goes back to this step. Every mutation is a function of
   the records, so each process's change is applied once; a killphrase is matched again. An update to an item the
   other process changed too replaces it, as the later save does in SQLite, but keeps a HOTP counter the other
   process advanced if the update left the counter alone, so a used code isn't generated again. After three
   conflicts in a row it throws `EncryptedVaultStoreError.conflict`. If the slot doesn't open with our wrap key any more (it was
   rewrapped or replaced), the store can't save again until the vault is unlocked again.
3. Encodes, compresses and seals the body with generation + 1, reseals the key box, and builds the new file
   bytes with the other slots copied unchanged.
4. Removes temp files a writer that crashed left behind. Each is an old copy of the whole file, which could hold
   items deleted since, under the same keys (C6). If one can't be removed, the save fails.
5. Writes a temp file, `.vault-slots.tmp-<random>`, and calls `F_FULLFSYNC`.
6. **Verifies** the temp file: reads it back, requires it to match byte for byte, opens our slot's key box and
   body from it, decodes, and compares with the new records. The read most likely comes from the page cache, so
   this proves the sealing and encoding round-trip, not what reached storage; `F_FULLFSYNC` is what covers that.
7. Renames the temp file over `vault-slots.v1`, then flushes the directory with `F_FULLFSYNC` (on Darwin, plain
   `fsync` doesn't flush the drive's cache).
8. Publishes the new records in memory and releases the lock.

If any step up to the rename fails, the temp file is removed, the in-memory records stay as they were, and the
error is thrown. `deleteItems(matchingKillphrase:using:)` returns `false` instead, exactly as it does for
"no match" today, so C2 holds. Search, killphrase matching and search passphrase matching are all in memory.

- **The rename is the commit point.** Once it succeeds the file holds the change, so a failure to `fsync` the
  directory afterwards doesn't undo it, and the change is published.
- **Waiting for the lock** polls with `LOCK_NB` and `Task.sleep`, so it doesn't block a thread, and gives up
  after 10 s, so a stuck holder can't hang the store, which would also stop the vault locking.
- **The file I/O is `SlotFileSystem`**, which tests replace to fail or crash at every step.

### Crash safety

| Crash or failure during | State afterwards | Recovery |
| --- | --- | --- |
| A save, before the rename | Old file intact; maybe a stray temp file | The next save, by any process, or the next unlock deletes the temp file. The change was never reported as saved. |
| A save, after the rename | New file, already verified | None needed |
| Disk full, or verification fails | Old file intact | Error shown; nothing changes in memory |
| A password change | Old or new file, never a mix | Either the old or the new password works |
| Turning the password off or on | Old or new file; the journal says `turningOff` or `turningOn` | The device key is tried on every slot. See [Turning the password off](#turning-the-password-off-and-why-it-doesnt-convert-back) |
| Slot growth | Old or new file; one rename covers every slot | None needed |
| Enabling the password | See [Migration](#migration-plain-to-encrypted) | Journal |
| An erase | The vault is as it was if the erase hadn't been journaled or removed anything yet; otherwise it's partly erased, and every vault is unreadable once the encrypted file is gone | Journal, or an encrypted mode with no vault left and the count of wrong attempts at the threshold: finished at the next launch, before any store opens. With no vault and neither of those, nothing is touched until the user confirms (see [Erasing](#erasing-after-failed-attempts-vault-34)) |
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
3. Build the file in memory: the header, slot `r` sealed (its `duressSlots` are ten random slots ≠ `r`), the
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
  truth. Delete the slot file and any temp files. The UI never said the password was set. If the SQLite store
  isn't there, something else has gone wrong (a lost state file, say), and the slot file might be the only copy of
  the vault, so nothing is deleted and the app shows its failure screen.
- Journal `encrypted(password), cleanup: plain`: finish deleting the SQLite files. This is idempotent.

**As built** (`VaultEncryptionConverter`, `VaultStorageRecovery`, VAULT-47), the steps above run in a slightly
different order:

- **Preconditions first.** A second conversion is refused before the first can suspend. The vault's size is checked
  against the largest slot before anything is journaled or derived, and a vault too large for it refuses with its
  own error (`vaultTooLarge`), which the UI can explain. The attempt counter is reset, so a count left in the
  keychain doesn't carry over to the new password.
- **The lock is held from the journal to the commit.** The conversion takes `vault-slots.lock`, journals
  `migrating`, and locks the store session, so the app's own writes finish first. Only then does it take the
  snapshot. An extension reads the plain store only while the state is a settled `plain`, and writes it only
  holding the same lock, checking the state again once it has it (`GuardedPlainVaultStore`). So a HOTP counter
  AutoFill or a widget advances can't land after the snapshot and be lost.
- **The failed-open archives** are confirmed by the caller, and their names go in the committing journal, so
  recovery deletes exactly those.
- **The commit is the committing journal's rename.** Every state write treats its rename as done once it's done:
  flushing the directory after it is attempted, not required, as for the encrypted file.
- **Undoing** a conversion that failed before the commit first reads the journal on disk. Only if it shows the
  conversion didn't commit does it delete the encrypted file, and only a file this conversion wrote, then remove
  the journal and switch the session back to the plain store. If the journal can't be read, the session stays
  locked and the next launch's recovery decides. If a deletion fails, the journal still says `migrating`, which
  recovery undoes the same way.
- **The backup settings** move into the real vault (VAULT-70). They're read first, before the attempt counter is
  reset, because reading the backup password asks the user to authenticate: if they don't, nothing has changed. They
  go into the snapshot's `vault.settings`, and are deleted from the keychain and `UserDefaults` after the commit.
- **After the commit**, "close the SwiftData container" is a hook the app provides (`releasePlainStore`, with
  `VaultRoot.plainVaultStore` releasable). The SQLite files, the rehash files and the confirmed archives are
  deleted, then the journal says `clearingSystemSurfaces` while the QuickType identity store is cleared and the
  widgets reloaded. The app runs those again at its next launch if it stopped first
  (`finishClearingSystemSurfaces`). A failure deleting the SQLite files is left for the next launch too.
- **The session** switches to the vault only if it hasn't locked since the conversion locked it: if the app went to
  the background meanwhile, it stays locked, and the vault opens with the password.
- **Recovery never deletes a possible only copy.** It deletes the SQLite store only if the encrypted file is there
  and has the size of one, and the encrypted file only if the SQLite store is there. Otherwise the app shows its
  failure screen. It checks the size rather than reading the file, because the file can only be read while the
  device is unlocked, and the app can launch in the background while it's locked. The file was verified before
  the commit, and only verified writes replace it.
- **Background time.** The conversion holds `vault-slots.lock`, and iOS terminates an app suspended while it holds
  a file lock in the App Group's container (`0xdead10cc`). So it asks for background time for all of it
  (`VaultBackgroundTime`, `.application` in the app). If that runs out anyway, recovery treats it as a crash.
- **Updates, not overwrites.** After the commit, each state write updates the state as it is then
  (`VaultStorageStateFile.update(_:)`), so an unlock attempt that raises the deadline meanwhile isn't undone.

**No step deletes the source before a verified copy is committed.**

### Turning the password off, and why it doesn't convert back

`VaultPasswordChangeService` (VAULT-48) changes the password, turns it off, and turns it back on.

**Checking the current password** is an unlock attempt (`VaultUnlockService.checkPassword(_:opensSlot:)`):
counted before deriving, the same derivation and sixteen trials, held to the deadline, and the count reset only if
it's right. It opens no body, whatever the password. Right means it opens **the open vault's** slot, so a password
that opens another vault is as wrong as any other, and the check never shows another vault is there.

**Changing the password** checks the current one, refuses a new one equal to it once both are in Unicode's
composed form ("must differ", identical in every vault), derives the new `K_pw` with the file's salt, and rekeys
the slot. One rename makes the change, so there's nothing to journal: either password works afterwards, never
neither. A new password that happens to open another slot is accepted silently (see
[Same passwords](#same-passwords)).

**Turning the password off** checks the current one. It then:

1. Makes a new device key `D`, replacing any there was.
2. Journals `turningOff`.
3. Rekeys the open vault's slot to `D`, and gives the file the `deviceKey` mode's protection.
4. Settles the mode by trying `D` on every slot, as recovery does (below): `encrypted(deviceKey)` if the rekey
   happened, and the journal is cleared.

**Turning it back on**, from `encrypted(deviceKey)`, needs no current password: device authentication opened the
vault. It resets the attempt counter, derives the new password's key with the file's salt, journals `turningOn`,
rekeys the slot, and settles the mode the same way: `encrypted(password)`, and `D`, which opens nothing any more,
is deleted.

Resetting the counter on device authentication alone is accepted, and doesn't conflict with MANIFESTO C4: with the
password off, device authentication opens the vault anyway, so the count guards nothing a coercer couldn't already
open, and a count left from before mustn't carry over to the new password. No deniability feature is removed.

**In the `deviceKey` mode** the app unlocks with device authentication only (`unlockWithDeviceKey()`): no
password, no attempt to count, no deadline. It opens the slot `D` opens, and moves the wrap stamp on as a password
unlock does, where it can: the stamp is readable only while the device is unlocked.

- **Settling, not assuming.** A turn off or on records the mode by trying `D` on every slot, holding
  `vault-slots.lock`, so what's recorded is what the file holds, whether the rekey worked or not. If a rekey fails,
  that leaves the mode as it was straight away, and a `D` made for it goes.
- **A mode that can't be saved.** Settling is tried three times. If the state still can't be saved, the change is
  made but the journal stays. Unlocking with a password then tries `D` on every slot first, before anything is
  counted. If `D` opens one, it's refused (`passwordChangeUnsettled`), so a right password is never counted as wrong
  while `D` wraps the vault, which with the erase after failed attempts could destroy it; `D` still opens it
  meanwhile. If `D` opens none, the vault is in the password form, and the attempt goes ahead, so a full disk doesn't
  stop the password unlocking once it's back on. The next change settles it first,
  the app's password service settles it and tries again when an unlock is refused
  (`settleInterruptedChange()`), and so does the next launch.
- **With the password off, unlocking with a password is refused** (`passwordIsOff`), again before anything is
  counted.
- **Recovery.** At launch, `turningOff` and `turningOn` are resolved by trying `D` on every slot: if one opens,
  the rekey happened (off) or didn't (on), and the mode is `encrypted(deviceKey)`; if none does, it's
  `encrypted(password)`. The vault is intact either way.
  - **While the device is locked**, after an app launch in the background, the file may not be readable. It's then
    in the password form, as turning the password off makes it readable after the first unlock, and turning it on
    makes it readable only while the device is unlocked again. So the mode is `encrypted(password)`, and the
    journal stays, for the unlock path or the next launch to settle, rather than a failure screen cached for the
    whole process.
  - **`D` is deleted whenever the mode is `encrypted(password)`**, once it's been shown to open nothing: after
    settling, and at every launch if one is left over, from a turn off that failed or a deletion that did. If the
    file can't be read, it waits.
  - **`D` missing in `encrypted(deviceKey)`** shows the failure screen, saying how to get the key back (see
    [Residual limits](#residual-limits)).
- **Locking waits for a rekey.** It runs as a call underway on the store session, so locking waits for it to finish
  and settle, as for a save, and a lock that comes first stops it before anything changes, `D` included.
- **Only the open vault's slot changes.** The header and every other slot stay byte for byte. From a duress vault
  it all behaves the same, and never touches the real vault.
- **Wrap times** come from the device's wrap stamp (`VaultDeviceWrapStamper`), the same one every wrap uses, never
  the clock directly, because they break ties when one password opens more than one slot. A clock set back would
  otherwise let a coercer choose which slot wins, and use "change the password" to test guesses without counting
  them.
- **Background time**, as for the conversion, because the rekey holds `vault-slots.lock`.
- **The state** is updated, not overwritten, as after a conversion, and every change to it, recovery's included,
  holds `vault-slots.lock`.
- **The lock file** is created readable after the first unlock (`completeUntilFirstUserAuthentication`), and one
  made earlier with the app's default class, complete protection, is moved to it. With the password off, the widgets
  and the app take the lock while the device is locked, and a file with complete protection can't even be opened
  then. The storage state and, in this mode, the encrypted file have the same class; `D` is readable after the first
  unlock.
- **`D`'s bytes** are zeroed after they're copied into the key, both on the way into the keychain and out of it, as
  far as the storage code can: the keychain keeps its own copy.

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

**Unlock, when a password is set.** The lock screen is VAULT-22's. The storage side is `VaultUnlockService`
(VAULT-46):

1. Increment the persistent attempt counter (VAULT-22 and VAULT-34) **before** deriving. Force-quitting then
   can't skip a wrong attempt. If the user still has to wait after earlier wrong attempts, say how long and try
   nothing.
2. Start the device's fixed unlock deadline, set during calibration (see [Key derivation](#key-derivation)).
3. Derive `K_pw` off the main actor, from the password's UTF-8 in Unicode's composed form (NFC), so it derives
   the same key however the keyboard composed its accents. Setting a password uses the same.
4. Try **every** slot's key box, with no early exit.
5. If exactly one opens, open its body. If more than one opens, pick the most recently wrapped (see
   [same passwords](#same-passwords)). Decode it. If none opens, open a decoy body instead (a random slot's, with
   a throwaway key, which fails), so every attempt opens exactly one body.
6. Drop `K_pw` and every `W_i`. They're CryptoKit `SymmetricKey`s, whose storage is zeroed on release. The
   Argon2 working memory is `memset_s`'d before it's freed.
7. Wait for the deadline. Then reset the counter and show the vault, or show the error.

Wrong, real and duress passwords all run the same derivation, the same sixteen trials and one body, and finish at
the same deadline. What differs afterwards is decoding time, which is proportional to what the vault shows anyway.

- **An attempt whose derivation and slot trials take more than two thirds of the deadline** raises it to 1.5
  times that before the attempt waits, so that attempt is held to the raised deadline too. Only that work counts,
  because it's the same whatever the password: the deadline is saved, so counting a vault's decode would make every
  later attempt, a duress one included, show how large the largest vault opened is. The work is timed in the thread's CPU time, so time the app spends suspended,
  or the device asleep, doesn't count; only an attempt that finished its work and is still wanted raises it; and
  it goes no higher than 5 s, about 1.5 times 32 passes on an iPhone four times slower than an M5 Max. A stored
  deadline above that is taken as 5 s.
- **Ties** in the most recently wrapped slot go to the lowest index. Wrap times are stamped by the device that
  wrapped the key, and only ever go forward on that device (see [Same passwords](#same-passwords)). A file restored
  from another device keeps that device's stamps.
- **Every unlock moves the wrap stamp on** to the latest of the stamp, now and the opened vault's wrap time, and saves
  it, under the file's lock, best effort (`VaultDeviceWrapStamper.noteUse(ofVaultWrappedAt:)`). It's saved every time,
  so real and duress unlocks do the same work, and the stamp shows when the device was last used, not when a key was
  last wrapped. Later wraps on this device also follow the opened vault even where the stamp was lost.
- **Failures after counting** (a vault that opens but can't be read, say) are reported at the deadline as well.
- **The counter is only reset when a vault opens.** If resetting fails, the vault stays locked and the error is
  shown, rather than opening with a count that would carry on.
- **An attempt underway when the app locks** is thrown away, and the vault stays locked. The session only
  switches to the vault if it hasn't locked since the attempt began, checked on the session itself
  (`switchTo(_:unlessLockedSince:)`), so a lock can't slip in between the check and the switch.
- **Unlocking needs a locked session.** With a vault open already it refuses without counting an attempt.
- **The opened slot's keys** stay with its store until the vault locks. Every other key is dropped at step 6.

**Lock.** This happens on background, or explicitly (VAULT-21), through `VaultUnlockService.lock()`:

- Await any in-flight write on the store actor.
- Switch the store session to `locked`.
- Drop the record store, `K_i`, the item caches and search text (`VaultDataModel.purgeVaultContents()`).

It's async, because the session waits for writes underway. The app lock's own purge hook is synchronous, so it
starts the lock in a task, as it already does for the purge.

- **The Require Unlock delay** still applies when the app goes to the background. While the password is set, the
  device locking locks the app and the vault at once, whatever the delay
  (`UIApplication.protectedDataWillBecomeUnavailableNotification`, `AppLockService.deviceWillLock()`), if the app is
  still running then. Neither the delay nor that notification runs in a suspended app, and iOS suspends an app soon
  after it goes to the background. So with a delay, the vault's keys can stay in the suspended app's memory until
  it comes back, or is terminated, and the app then locks if the delay has passed. With "Immediately", the vault
  locks as the app goes to the background. Without the password the delay stands, as the plain store has no keys to
  hold.
- **A lock racing an unlock.** Unlocking waits for any lock of the vault underway. If the app locks during an
  attempt, the attempt's result is thrown away and the vault locked again after it, in case it opened after the
  lock.
- **A lock during a conversion** finds the plain store, which the app lock only hides, and the conversion then opens
  the encrypted vault. Setting the password locks it again as soon as the conversion finishes.

**Zeroing, honestly:**

- Keys live in `SymmetricKey` and are zeroed. `K_pw` goes straight from the derivation's wiped buffer into one.
- Buffers the storage code owns are `memset_s`'d when it's done with them: the key box and body plaintexts, the
  compressed payload, the compression scratch buffer, the JSON encoded for a save, and the JSON decompressed to
  read a vault, including when a save verifies. The compression output is sized up front, so it never leaves
  copies behind by reallocating.
- The records decoded from the JSON, which are Swift `String`s and `Data`, can't be reliably zeroed, and nor can
  the JSON coders' own buffers, the compression stream's internal state, or CryptoKit's. They're freed and eventually reused. Process memory isn't readable by
  other apps, but a forensic tool with code execution on an unlocked, exploited device can read a suspended
  process.
- The password comes from a `SecureField`. The binding is cleared after use, but the `String` isn't zeroed.

**Store session.** `VaultRoot.vaultStore` is a `static let PersistedLocalVaultStore` today. It becomes a
`VaultStoreSession` that implements the same protocols and forwards to `plain(PersistedLocalVaultStore)`,
`unlocked(EncryptedVaultStore)` or `locked`. `VaultDataModel` already takes protocol types, so it barely
changes.

**In the app (VAULT-22, as built).** `AppLockService` works through `EncryptedVaultPasswordService`, which follows
how the vault is stored as the password is set, changed, turned off and back on:

- **Password mode:** device authentication, then the password, through `AppLockPasswordUnlocker` (VAULT-34's erase)
  and `VaultUnlockService`. A turn off or on that couldn't record how it ended is settled from the file and the
  password tried again. If it turns out the password was off, the vault opens with the device key, as device
  authentication has passed.
- **Device-key mode:** device authentication alone, which then opens the vault with `D`
  (`openVaultWithoutPassword()`). With the app lock off as well, the vault opens at launch.
- **Plain:** as before.
- **Locking** locks the vault too (`lockVault()`), and unlocking waits for that to finish first. The plain store is
  only hidden, as before. The device locking locks the app and the vault while the password is set (see
  [Unlocking and locking](#unlocking-and-locking)).
- **The mode is re-read** from the storage state after every change and settle, so a change that threw after its
  rename can't leave the lock asking for the wrong thing. A password refused because the password is off opens the
  vault with the device key, as device authentication has passed.
- **Setting the password** converts the plain store, unless it opened this launch only after being set aside (then
  it doesn't hold the vault). Copies set aside earlier are deleted once the user agrees, and the setup screen says so
  first. Setting it turns erasing after failed passwords off. The screen names the precondition that failed:
  phrases still being updated, the vault too large, or a store that didn't open.
- **Background time** covers every conversion and rekey (`VaultBackgroundTime.application`).

## Duress vault (VAULT-23)

The format serves VAULT-23 directly:

- **Sixteen slots always exist.** A file with a duress vault looks exactly like one without.
- **Unlock timing is identical,** as described above.
- **Each vault is a full payload,** with its own items, tags, killphrases and per-vault settings: backup
  password, backup events, auto-backup configuration and the "backup password is set" record. VAULT-70 moves
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

**As built** (`VaultDuressSlots`, `EncryptedVaultStore.makeDuressVault(password:)`, VAULT-51):

- Only W's slot is written. V's isn't sealed again, so V keeps its generation, and two copies of the file show no
  change in V's slot. They do show W's slot changed, and not as a save would change it: creating a vault gives the
  slot a new nonce, and a save never does. So two copies show that a vault was created, or replaced, in that slot
  between them (see [Residual limits](#residual-limits)). Reusing the old nonce would hide this, but a writer still
  holding the vault that was replaced could then write over the new one, so it isn't done.
- The new password's key is derived as unlocking derives it (NFC, the file's parameters), off the main actor, then
  the file is replaced under its lock and verified, like any save: W must open with the new key and decode to exactly
  the empty vault, and V's key box must be unchanged.
- It isn't an unlock attempt, so it doesn't touch the attempt counter or the unlock deadline.
- Every list a duress vault gets, taken whole, is a uniformly random choice and ordering of ten of the other slots,
  as the first vault's is, so a list doesn't show which kind of vault holds it.
- A vault whose list isn't ten distinct slots other than its own (only a vault the app didn't write) makes no duress
  vault, rather than guessing where one goes.

### Same passwords

- A new password equal to the password of **the vault you're in** is refused: "must differ from the app lock
  password". That check is identical in every vault.
- A new password that happens to open **another** slot is accepted silently. Refusing it would be an oracle: a
  coercer could test guesses through "make duress database", bypassing the unlock delay and the VAULT-34
  counter.
- If more than one slot opens at unlock, the most recently wrapped wins. That's the vault just created, which
  matches "the new password opens a new empty vault". The older one becomes unreachable but isn't destroyed. If
  the colliding password is the real one, the coercer already knew it.
- **Recency can't come from the wall clock.** A coercer inside a duress vault could otherwise set the clock back,
  make a duress vault with a guess at another vault's password, lock, and unlock with the guess. The new vault
  would be older than every other, so a right guess would open the vault it matched, and a wrong one the empty new
  vault. Every unlock would succeed and reset the attempt counter: unlimited guessing, with no delay or erase, that
  opens the real vault on a hit. So every wrap (creating the first vault at conversion, making a duress vault,
  rewrapping) is stamped through `VaultWrapStamping` by `VaultDeviceWrapStamper`:
  `max(now, the last stamp + 1 ms, the previous wrap time + 1 ms)`, where the previous wrap time is the slot's own,
  or, for a vault made from another, that vault's. The stamp is saved before the wrap is made, in a keychain item on
  this device only, in the App Group's access group. Every vault that opens raises it to its own wrap time.
- **What's left:** a device whose stamp is missing or older than the real vault's wrap, because its keychain was reset
  or it's a new device restored from a backup, and where the user hasn't opened the real vault since. There a duress
  vault made with the clock set back is stamped only after the duress vault it's made from, and can be older than the
  real vault.
- **The stamp is readable at rest** by forensic keychain tools. If it only moved when a key was wrapped, someone with
  one vault's password could tell a wrap was made after it: a duress vault made, or another vault's password
  changed. So it moves on every unlock too, and always to at least now, and it only ever says when the device was
  last unlocked, as the file's modification time does.
- **As built**, the check tries the new password's key on the open vault's own key box and nothing else, so its
  result depends only on the open vault. A vault whose key is wrapped by the device key (password off) never
  matches.

### Everything else for VAULT-23

- **Delete All Data** empties the open vault's slot and keeps the slot and the password that opens it. It deletes
  the vault's backup password (VAULT-60, below). In the same write it fills every other slot with fresh random
  bytes (VAULT-74), so every other vault goes with it: the duress vaults from the real vault, and the real vault
  and every other one from a duress vault. It changes every other slot whether or not it held a vault, so neither
  the file afterwards nor two copies from either side show whether others were there. It's the same in every
  vault. Resetting just a duress vault is done by making a new one from the vault above it, which replaces it.
- **Turning the password off** rekeys the open vault only (see above).
- **Backups and auto-backup** read only the open vault. VAULT-23 must keep each vault's auto-backup destination
  and retention cleanup in that vault's settings, so a duress vault never deletes or overwrites the real one's
  backups. As built in VAULT-70: see below.
- **Item dates.** Created dates inside a duress vault show how recently it was filled. That's outside storage,
  but VAULT-23's guidance should mention it.

### Each vault's backup settings (VAULT-70)

**As built** (`VaultBackupSettings`, `OpenVaultBackupSettings`, `DeviceBackupSettings`):

- **In the payload.** Each encrypted vault keeps its own in `vault.settings`:
  - the backup password's derived key, and when it was set;
  - the last backup event;
  - the auto-backup configuration, including the names of the files its auto-backup wrote;
  - the hint its PDF backups print in plain text.

  A new duress vault starts with none set, never a copy of the vault it was made from. Importing over a vault's data
  keeps them, as it does the plain store's. Deleting its data keeps them too, except the backup password and its
  record, which Delete All Data deletes, in the plain store as in an encrypted vault (VAULT-60). Kept, the password
  would restore any backup of what was deleted without anyone typing it, and the device authentication in front of
  Restore is no gate against someone forcing the user (MANIFESTO C4). The erase deletes it for the same reason. The
  paper size stays device-wide.
- **The plain store's stay where they were:** the backup password and its record in the keychain, the rest in
  `UserDefaults`. Turning encryption on moves them into the real vault (see
  [Migration](#migration-plain-to-encrypted)):
  - The backup password is read before anything changes, because reading it asks the user to authenticate.
  - The rest is read once the session has locked, so a backup that finishes while the user authenticates isn't
    lost.
  - They're deleted after the commit. If that fails, or the app stops first, every launch with the vault encrypted
    deletes them, with the password on or off.
- **Following the open vault.** `OpenVaultBackupSettings` is what the backup password store, the backup event
  logger, auto-backup and the PDF backup read and write through, so none of them knows about vaults. It holds the
  plain store's device-wide settings, the unlocked vault's own, or none while the app is locked. It reads them
  whenever the store session switches vault or locks, and when it's first set up
  (`VaultStoreSession.openVaultChanges()`). Until it has, it has none.
- **Never into another vault.** A change is saved only while the vault it was read from is still open
  (`VaultStoreSession.whileOpen(_:_:)`), and a change meant for a vault that has been locked or replaced is dropped.
  That holds for the plain store as well:
  - Each time the session opens the plain store is a different open vault, even for the same store.
  - So a change read before an erase or a conversion locked the session can't put back settings that were just
    deleted.
  - An auto-backup configuration, an event and a PDF hint each carry a token for the vault they were read from.
    Saving with an earlier vault's token is refused.
- **Events** go into the vault a backup was made of, which is the vault open when the backup started. That covers a
  PDF export, a device transfer and an auto-backup. If that vault isn't open any more when the backup finishes, the
  event is dropped.
- **The backup password** of an encrypted vault is only read once the user has authenticated, as the keychain asks
  for the plain store's.
- **Auto-backup** (`AutoBackupServiceImpl`) follows every change of vault:
  - Its configuration and status are the open vault's at once.
  - The previous vault's destination is cleared at once, so a backup of it that's still underway can't write there
    any more.
  - The open vault's destination is set up only once that backup has finished or stopped, so the backup can't
    write there either.
  - A backup stops without writing if the vault changes while it's made, and it records, logs and shows nothing
    in any vault other than its own.
- **Backup files.** A provider never replaces a file, including one that's only in iCloud for now. If the name is
  taken, perhaps by another vault's backup made in the same second, the backup is written as `-2`, `-3` and so on.
  - Cleaning up deletes only files the vault's own auto-backup wrote. It never deletes another vault's, or one the
    user put in the folder.
  - It forgets a file once it has deleted it, or once the provider says the file is gone. A file that's only in the
    cloud, or that one listing missed, is still there.
  - It forgets files that are gone even when backups are kept forever, so the list doesn't grow for them.
- **Seeding the plain store's list, once.** Cleaning up used to delete every auto-backup in the folder. A plain
  store configuration saved before the files were recorded is seeded once from the folder, with every file the old
  cleanup would have deleted, so those backups are still cleaned up. An encrypted vault never seeds its list, since
  the folder could hold another vault's backups. A conversion that happens before the seed has run leaves those
  older files for the user to delete.
- **The Backups page** shows the open vault's last backup, its staleness, and whether it has a backup password
  (`VaultDataModel.openVaultDidChange()`). It follows as soon as the settings have reloaded, before auto-backup,
  which may wait for a backup to finish. Anything read for the previous vault that finishes after the change is
  dropped: a backup password being loaded or set, and the payload hash.
- **Erasing** (VAULT-52) needs nothing more:
  - An encrypted vault's settings go with the file.
  - The erase deletes the plain store's settings from the keychain and `UserDefaults`.
  - Auto-backup forgets its configuration and its providers' folders, stops any backup underway, and backs up
    nothing until the fresh plain store opens.
- Nothing logs, prints or measures which vault is open (MANIFESTO C3).

What's left:

- **A backup written just as the vault changes** is in the previous vault's destination, but isn't recorded in its
  settings, so its cleanup never deletes it. A backup that hadn't been written yet isn't made, and the vault is
  backed up the next time it changes.
- **A shared destination.** Two vaults auto-backing up to the same folder each leave a series of backups there.
  The names don't say which vault wrote which, but two interleaved series show that more than one vault is backing
  up. The folder is the user's choice, and VAULT-23's guidance should say to use a different one for a duress
  vault, or none.
- **The folder picker remembers.** The system's folder picker (`.fileImporter`) opens where it was last used,
  whichever vault that was in. Choosing a destination in a duress vault can therefore start in the real vault's
  folder. The app can't clear that.

## Erasing after failed attempts (VAULT-34)

**Erase is key destruction.** Every wrapped data key lives in `vault-slots.v1`. Erasing does the following, in
order, idempotently, and journaled so a crash mid-erase finishes at next launch:

1. Unlink `vault-slots.v1`, the temp files and the lock file.
2. Delete the keychain items: device key, killphrase and search passphrase HMAC keyrings, backup password and its
   record, attempt counter, wrap stamp.
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

**As built** (`VaultEraser`, VAULT-52):

- **The entry point** is `VaultEraser.erase()`, and in the app `VaultRoot.eraseVault()`, which also reads and writes
  the fresh store afterwards. The unlock service's `wrongPassword(reachesEraseThreshold:)` says when an attempt is the
  tenth wrong one in a row or later. VAULT-34's lock screen calls it then, if the user has turned erasing on. Tests
  call `erase()` directly.
- **Before step 1,** it locks the store session, lets go of the plain store if one is open (a hook), and journals
  `erasing` in the storage state, in place of any other transition underway: whatever a conversion had left to do,
  the erase does or makes moot. Until the journal is in place nothing has been removed, and a count of ten or more
  is still in the keychain, so the next wrong attempt erases again.
- **If the journal can't be written,** perhaps because the disk is full, it does step 1 first, which frees space,
  and tries again. It removes the plain store before the encrypted file then, so the app can't stop with the
  encrypted file gone and a plain store left, which recovery keeps as a possible only copy. If the journal still
  can't be written, or the app stops first, the device is in an encrypted mode with no vault at all, and the count
  of wrong attempts is still at the threshold: the keychain items aren't deleted until the journal is in place. That
  count shows the erase was meant, so recovery reports an erase to finish.
- **With no vault, no journal and a count below the threshold,** nothing shows an erase was meant. A restore or a
  move to another iPhone can bring back the storage state without the file, and erasing then would delete every
  keychain item, the backup password and `D` among them, and recovery would delete the file if it turned up later.
  So recovery touches nothing and throws `vaultMissing`. The failure screen says how to restore the vault, and
  offers to erase and start again, which runs only once the user confirms (`MissingVaultViewModel`).
- **Step 1 removes every copy of a vault:** the encrypted file first, then its temp files, the plain store's files
  and its failed-open archives, which are plaintext copies, and last the lock file, so a writer can't take a new
  lock while the encrypted file is still there. It holds the file's lock while it does, if
  it can, so a save underway in the AutoFill extension can't put the file back: a save reads the file under the lock,
  and fails if there isn't one. Before the journal is cleared, it checks again, holding the lock, that a writer that
  had stalled hasn't put the file back.
- **Step 2** deletes every keychain item: the killphrase and search passphrase HMAC keyrings, this device's own keys
  and those restored backups brought, the backup password and its record, the attempt count, the wrap stamp
  (VAULT-51), which shows a password vault was used and about when, and the device key (VAULT-48), which opens the
  vault while the password is off, and would show it had been turned off. `VaultIdentifiers.SecureStorageKey` lists
  every item, however it's stored, and the erase switches over all of them, so a new one doesn't build until it's
  decided what an erase does with it.
- **Step 3** clears the vault's settings still kept on the device: the last backup event, the auto-backup
  configuration, and the PDF backup's hint. They'd show a vault had been erased, and the auto-backup configuration
  says where its backups are: once a new backup password is set, auto-backup would write there, and its retention
  clean-up delete the erased vault's backups. The auto-backup service and the data model read them at launch, so a
  hook makes them forget their copies too, and the providers their folders. It turns off erasing after failed
  passwords, which only means anything with a password. It also removes the pending rehash files and backup PDFs
  left in the temporary directory. The storage state goes last, when the journal is cleared.
- **Step 4** tries the QuickType store a few times, and then carries on without it: while the password is on it's kept
  empty already, and a store that's stuck mustn't leave the vaults half erased.
- **Step 5** creates the store without the plain store's failed-open recovery, so it never sets a copy aside, then
  clears the journal, which removes the state file, and switches the session to the new store.
- **Unlocking refuses while the journal says `erasing`** (`VaultUnlockError.erasing`), even with the right
  password, so a vault whose file couldn't be removed never opens again, in the app or AutoFill.
- **At launch**, recovery reports `erasing` before looking at anything else, and deletes nothing itself. The app
  opens no store, and `setup()` finishes the erase (`InterruptedEraseViewModel`). The vault's views wait for it, so
  nothing loads the keys it deletes first. If it fails, they stay hidden behind a screen that says it didn't finish
  and offers to try again. It never runs again once it's finished, which would erase the fresh store. Every step is
  safe to repeat. The extensions treat the vault as locked until then.
- **A failure** stops the erase with the session still locked. Calling `erase()` again, or launching again, finishes
  it.
- **What the app holds in memory** from the vault itself is the caller's to reset after an erase while the app runs:
  the items, the backup password, and the killphrase and search passphrase digesters, which were made from the keys
  step 2 deletes. `purgeSensitiveData()` keeps the digesters, so `VaultRoot.eraseVault()` resets all of them
  afterwards (`VaultDataModel.resetAfterErase()`), and reloads the fresh store.

**The setting** (VAULT-34) is "Erase Vault After 10 Failed Passwords", in the App Lock Password's Settings screen,
next to Change, Turn Off and the duress password. It's off by default, as iOS's Erase Data is. Turning it on or off
takes the current App Lock Password (`VaultPasswordChangeService.setErasesAfterFailedPasswords(_:current:)`), checked
as changing the password checks it: counted and held to the deadline, but it never erases, as the vault is open.

It's a setting of the device, not of a vault, like the attempt count (`AppLockSettingsStore.erasesAfterFailedPasswords`,
in the shared defaults, stored only while it's on). Every vault's lock screen erases by it, every vault shows it the
same, and each vault's own App Lock Password turns it on or off for all of them, a duress vault's included (see
"Consequences to accept"). Turning the password off, or back on, turns it off. The erase removes it.

**The lock screen** shows only how long to wait, never how many attempts are left. When the tenth wrong password in
a row comes back and the device's setting is on, the app's password service (through `AppLockPasswordUnlocker`)
erases before it answers, so the lock screen never shows the password was wrong, and answers `.erased`. The app then
opens the fresh, empty plain vault with no password, as after a new install, with no message: a notice would be a
record that an erase happened (C6). Anything that was waiting to open an item is dropped, even if the erase finishes
after the app has locked again. The app lock stays on, asking for device authentication only: it's a choice the user
made for the device, not something of the vaults the erase removed. Before the tenth, a right or duress password
never erases, and resets the count. If the erase fails once it's journaled, no vault can open, and the next attempt,
whatever the password, finishes it; so does the next launch.

**A right attempt that's thrown away still resets the count.** If the app locks, or the task is cancelled, while an
attempt is waiting out the deadline, its result is thrown away; but if the password opened a vault, the count is
reset first, as it would have been, the same for a real and a duress password. Otherwise a right tenth attempt
interrupted by a phone call would leave ten counted, and the next attempt would erase. Every attempt holds background
time (`VaultBackgroundTime`) until it's finished, so the app isn't suspended in between. An attempt the app is
stopped in the middle of, by force-quitting it, stays counted, as a wrong one would.

**An erase that's due comes first.** Before it tries any password, the app reads the count
(`hasReachedEraseThreshold()`), every time, erasing on or off, so an attempt takes the same time either way. If ten
or more are counted and the setting is on, it erases instead, whatever was entered, the real and duress passwords
included. The count gets there only through attempts that weren't found right: a wrong tenth attempt the app was
stopped in the middle of, before it could erase. Settings and AutoFill never try the attempt that would make ten.

**Settings never tries the tenth attempt.** Checking the current password, to change it, turn it off, or turn erasing
on or off, counts like any other attempt, but the one that would make the tenth wrong in a row isn't tried or counted
(`VaultPasswordChangeResult.onlyAtTheLockScreen`), erasing on or off. The screen says to lock Vault and enter the
password on the lock screen, and never why. So the attempt that could erase always happens at the lock screen, where
an erase is immediate and visible.

**AutoFill never erases.** The extension counts its attempts with `stoppingBeforeEraseThreshold`: an attempt that
would be the tenth in a row, or later, isn't tried or counted (`VaultUnlockError.stoppedBeforeEraseThreshold`), and
the sheet says "Open Vault to enter your App Lock Password." That's safer than erasing in the extension:

- An erase is a run of file and keychain steps. The system can stop an extension at any point, and it has little
  memory, while the app, if it's running, would be finishing the same erase from its own launch recovery.
- Refusing needs nothing but a read of the count, so there's no half-done state, and no free guess: the attempt
  that could erase only ever happens in the app, where a wrong one erases before it's shown.
- It refuses whether erasing is on or off. Refusing only when it's on would show that it's on, and that this is the
  last attempt before an erase, which is the countdown the lock screen never shows. Refusing either way shows only
  what the person guessing already knows: they've got it wrong nine times.

The counter decides while it holds the count against every process (`withExclusiveAccess(_:)`), so an attempt the
app counts at the same moment, with both on screen on an iPad, can't make the extension's the tenth.

## Widgets, AutoFill and QuickType

| Surface | `plain` | `encrypted(password)` | `encrypted(deviceKey)` |
| --- | --- | --- | --- |
| Widgets | As today | Locked placeholder. `OTPWidgetItemEntityQuery` returns nothing. `reloadAllTimelines()` when the password is turned on, so archived timelines with codes are replaced. | Codes show. The extension opens the slot file with the device key only to read it: without the file's lock, leaving nothing behind (no lock file, no wrap stamp), afresh for every read, and every read checks the mode is still `deviceKey` (VAULT-50). See residual limit 11. |
| Widget HOTP increment | As today | Unavailable | Through the app: the small widget links to it, as the lock-screen widgets already do. The widget hasn't the memory to save the file (residual limit 11). |
| AutoFill sheet (`prepareOneTimeCodeCredentialList`) | As today | Asks for the app lock password in the sheet. Checks memory headroom, derives with 64 MiB, opens the slot. Writes (HOTP) go through the same `flock` and generation check. Never Face ID alone (C4). | Device authentication, if the app lock is on, then the device key opens the slot, only then, and only if the storage state still says `deviceKey`, before and after opening. Every call to the open vault checks the mode again, and a save checks once more under the file's lock (`VaultAccessGuard`), so a sheet left open while the password is turned on, or the vault erased, shows and saves nothing. Checks memory headroom first, with the password path's figure (residual limit 11). |
| QuickType (`provideCredentialWithoutUserInteraction`) | As today | Identity store emptied when the password is turned on, and never written while it's on. Requests return `userInteractionRequired`. | Identity store filled again from the vault the device key opens when the password is turned off, if Vault is turned on as an AutoFill provider, and kept in sync. Journaled (`syncingSystemSurfaces`), so launch finishes it. A write the password came on during is emptied again. Requests read the vault with the device key in a session of their own, locked straight after. |

Residual: a configured widget's saved `OTPWidgetItemEntity` (issuer, account name) sits in the system's widget
configuration, which the app can't edit. Turning on the password should tell users to remove existing widgets.

## Backups, killphrases and everything else

- **Backups, exports, device transfer, auto-backup.** Unchanged, except that each vault has its own backup
  settings (VAULT-70). They export from the unlocked store and encrypt with the open vault's backup password.
  Auto-backup is only ever triggered by changes in the running app, and no background
  task exists (no `BGTaskScheduler`), so nothing needs the vault while it's locked. The backup format keeps its
  own KDF and container.
- **Backup sizes (VAULT-75).** A saved backup, a PDF or an auto-backup, is padded to just under a fixed size: 32 KiB
  of ciphertext, about 130 typical items, or the first power of two times that it fits. So a backup doesn't show
  how much its vault holds, and one found next to a duress vault with few items can't show that a bigger vault
  exists. The padding is random bytes in the payload's `obfuscationPadding`, inside the encryption: padding in the
  outer container would leave the real length readable without the password. The format is unchanged, so older
  builds restore it. A device transfer, which saves nothing and shows each QR code for two seconds, keeps a random
  amount. A backup the duress vault's backup password can't open is still a bigger tell than its size, which is
  guidance for the user (the FAQ's duress page), not something the app can hide.
- **Killphrases.** Matching and deletion happen in memory, then the file is replaced. The deleted item is gone
  from the live file at once, as it is from the SQLite store's files since VAULT-55 scrubs them after the
  delete.
- **Search passphrases.** Matched in memory with the same digester.
- **HMAC keys.** The killphrase and search passphrase keys stay device-wide keychain items. Per-item salts make
  sharing them across vaults harmless. Each is a keyring (`HMACKeyring`): this device's own key, which makes every
  new digest, and the keys that restored backups brought, which are only matched against. Every match tries every
  key, each with a constant-time comparison (`isValidAuthenticationCode`), and none is skipped once one matches, so
  a match behaves the same on no match and on failure as it always has (C2).
- **HMAC keys in backups.** Every backup, auto-backup and move to another device carries every key on both
  keyrings, inside its encryption (`killphraseKeys` and `searchPassphraseKeys` in the payload). Restoring one adds
  the keys this device doesn't have, never synced and with the same access as its own, so the backup's killphrases
  still delete and its passphrase-hidden items can still be found, on another iPhone or after an erase. That's the
  only way they can: a digest can't be made again without its phrase, and a restored vault whose phrases never match
  has items no search can reach.
  - **Accepted:** anyone who can decrypt a backup can test guesses at its killphrases and search passphrases offline,
    at the speed of HMAC-SHA256. They can already read every item in it, passphrase-hidden ones included, and see
    which items have a killphrase. What the keys add is the phrases themselves, so a phrase shouldn't be a password
    used anywhere else.
  - The keyrings are the same whichever vault is open, so a duress vault's backup carries the same keys as the real
    vault's. How many keys there are shows how many other devices' backups, or backups from before an erase, have
    been restored here.
  - Backups made before the keys went with them bring none. Their phrases only match on a device that still has the
    keys they were digested with, which the FAQ says.
  - Older builds ignore the two fields: the payload's version is unchanged, and its default `Codable` skips keys it
    doesn't know.
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
| `UserDefaults` and keychain settings | Dates, a payload hash, auto-backup configuration, the PDF hint, the backup key | No backup settings: each vault's are in its payload (VAULT-70). App preferences stay. |
| Wrap stamp (keychain, this device only) | Not there | When the device was last unlocked, or a key last wrapped: the same as the file's modification time |
| Erasing after failed passwords (shared `UserDefaults`, VAULT-34) | Not there | Whether it's on, stored only while it is. Nothing about which vault turned it on or off. In device backups too. |
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
   app can't open can't be re-randomized. They also show when a vault was created in a slot, or one replaced:
   its slot nonce changes, which a save never does. So they show a duress vault made between the copies.

   Mitigations:
   - Use the duress vault now and then. Every save also re-seals it at the full slot size, which covers limit 4.
   - An opt-in "exclude the vault from device backups". It isn't offered for now, and it trades against
     restoring from a device backup.
3. **Nested duress creation.** The real vault is guaranteed untouched for eleven levels at N = 16, L = 10. Beyond
   that it isn't; see [Duress vault](#duress-vault-vault-23).
4. **Slot size.** The slot size bucket reveals that some vault once exceeded the previous bucket. It starts at
   1 MiB, about 3,500 items, so this only applies to very large vaults.

   Growth also leaves a mark in the vaults it didn't write. Their key boxes keep their real body length, shorter
   than the slot, until each saves again. So if a vault opened under coercion has a body length below
   slot size − 116 bytes, it can't be the one that grew the file, which shows another vault did. Saving in the
   duress vault now and then (limit 2) removes the mark.
5. **Fixed KDF parameters.** They're calibrated once, on the device that creates the file.
   - Raising them later needs a new format version whose unlock derives under both parameter sets (twice the
     time) during a transition, or an erase and re-create.
   - Restoring the file onto a slower iPhone makes unlocking proportionally slower. The 32-pass ceiling bounds
     it.
6. **Memory.** Decrypted items can't be reliably zeroed after locking (see above).

   Nor can a test show that every buffer the storage code zeroes is zeroed. Where the code allocates the memory
   itself, tests check it's zeroed by the time it's freed: the Argon2 working memory, the copy of the password it's
   given, and the compression scratch buffer. The key box and body plaintexts, the compressed payload and the JSON are
   `Data`, which Foundation allocates and frees. They're `memset_s`'d where the storage code is done with them, but no
   test sees them freed, so a copy made on write, such as one a slice kept alive would cause, would leave the original
   unwiped without failing anything.
7. **Rollback.** Someone who can write the app's files can put back an older copy of the file. Local storage
   can't prevent this.
8. **Surfaces outside storage.** Configured widget entities, keyboard learning, item dates inside a duress
   vault, auto-backups from more than one vault to the same folder, and the folder picker's last folder.
9. **A vault's own key box.** Anyone with a vault's password can read when its key was last wrapped, which for a
   duress vault is when it was made, as its item dates show anyway. Its generation doesn't help: it starts at a
   random value in a range far wider than a vault's saves, so a new vault's looks like a long-used one's.
10. **Restoring onto another iPhone with the password off.** In `encrypted(deviceKey)` the vault opens only with
    `D`, which is in the keychain. A backup restored onto another iPhone brings keychain items only if it's
    encrypted, or from iCloud. After an unencrypted computer backup is restored onto a different iPhone, `D` is
    gone, and the password the vault had before doesn't open it either: turning the password off rewrapped the key
    and rotated `K_i`. Today's plain store would restore fine. The app shows its failure screen, which says to
    restore an encrypted or iCloud backup, or a backup PDF, and the turn-off screen warns about it beforehand.
11. **Extension memory with the password off.** The file is at least 16 MiB, and reading it with the device key
    reads all of it.
    - A widget extension gets about 30 MiB, so a large vault may take a widget over its limit. The system then stops
      it, and it shows its placeholder. Nothing is counted or written.
    - A save needs twice the file plus four times the JSON plus 16 MiB, which a widget never has. So the widget
      sends a HOTP increment to the app instead of making it.
    - AutoFill checks the password path's headroom (64 MiB plus the file plus 16 MiB) before it opens the vault with
      the device key, which needs less. That's stricter than it has to be, so on a device short of memory the sheet
      may send the user to Vault when it could have opened the vault.

    Reading only the slot a key opens, rather than the whole file, would fix the first two. It needs a format
    change.

## Test strategy

- **KDF.** RFC 9106 Argon2id test vectors and the reference repository's known-answer tests. Determinism, zeroing
  of working memory, and a memory high-water check: with the App Lock Password's 64 MiB, a derivation holds that one
  block and nothing more. A derivation can't be cancelled once it has started, as it's one call into the reference
  implementation: an unlock cancelled while it waits for its deadline throws its result away instead.
- **The shipped parameters.** One test sets a password with 64 MiB and passes calibrated on the machine it runs on,
  then unlocks and refuses a wrong password. Every other test uses cheap parameters.
- **Calibration**, with an injected timer:
  - Floor and ceiling clamping.
  - The fastest of three runs is used.
  - The deadline is computed and only ever raised.
  - The header carries exactly the chosen parameters.
  - A file created with one set of parameters opens on a "device" that would have calibrated differently: the slot
    file fixture, below.
- **Format.**
  - Round-trip every field.
  - Wrong password, wrong slot and wrong header all fail closed.
  - Flipping any single byte of the header, key box or body makes the slot fail to open.
  - Growth preserves other slots, and they still open.
  - Every slot has identical length.
  - Plaintext markers seeded into items never appear in the file bytes.
  - The compression scratch buffer is zeroed before it's freed, checked as the KDF's working memory is.
- **Golden fixtures** (VAULT-86). Files in the stored formats, made once by the app's own code and never made
  again, in `Vault/Tests/VaultFeedTests/Fixtures/` and `Vault/Tests/VaultBackupTests/Fixtures/`. A round trip can't
  catch a change made to the writer and the reader together, such as the AAD layout, the key box layout, a renamed
  payload field or a change to the padding, which would stop every existing vault opening. These can.
  - A whole `vault-slots.v1` file, with cheap Argon2id parameters in its header: a real vault, a duress vault made
    from it, and random slots. It's stored as its header and the two slots that hold vaults, and the test rebuilds the
    random slots around them. Each password opens only its own slot, to exactly its items, tags and settings, and a
    wrong one opens nothing. It also unlocks on a device that would calibrate differently.
  - An encrypted note and a recovery phrase, each as a payload stores it. Each decrypts to its text with its
    password.
  - A populated backup padded to 32 KiB, and the same backup padded by a random amount, as every backup was before
    VAULT-75. Each decrypts to the backup it was made from, and the encryptor, given the fixture's salt, IV and
    padding, writes it again byte for byte.
  - A format change adds a fixture and keeps every old one. Each fixtures folder's README says how its fixtures were
    made, and how to add one.
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
- **The app lock, over the real vault.**
  - Every `LocalAuthentication` error the lock tells apart. With no device passcode, the lock stops at device
    authentication, never asks for the password, and counts nothing; once a passcode is set up again, the password
    opens the vault.
  - Opening the duress vault after the real one, and the other way round, leaves nothing of the first in the data
    model.
  - Erasing: the data model forgets the erased vaults and their keys, and carries on with the fresh one.
  - Each launch recovery failure leads to the failure screen that says what to do.
  - The lock screen's countdown, on an injected clock, gives the password field back once the wait is over.
  - Real Face ID and passcode prompts can't run in the tests, so they're checked on a device before each release
    (`RELEASE.md`).

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
11. Erasing after failed passwords (VAULT-34) is a setting of the device, and any vault's own App Lock Password turns
    it off, a duress vault's included. So someone who has the duress password can turn it off, and guessing on the
    device is then limited only by the escalating waits: about one guess an hour after the ninth wrong one. That's
    accepted. Erasing only ever stopped guessing on the device: someone who can copy the file guesses offline
    regardless, and that's what the key derivation and the password's strength are for. Letting only the vault that
    turned it on turn it off for real was tried, and dropped: a vault showing it off while it stayed on would show
    another vault had turned it on, and a vault that owned it could be replaced by making a new duress vault, leaving
    no vault able to turn it off.
12. A backup carries the killphrase and search passphrase keys, so anyone who can decrypt it can test guesses at its
    phrases offline. That's accepted: it's the only way the phrases keep working once the backup is restored, and
    the backup already holds every item in full (see
    [Backups, killphrases and everything else](#backups-killphrases-and-everything-else)).

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
      and retention. Split out as VAULT-70.
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
