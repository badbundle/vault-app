# Golden fixtures

Files in the formats the app stores, each made once by the app's own code and kept exactly as it was made. The
tests in [`../GoldenFixtures`](../GoldenFixtures) open every one and check it holds what it was made with.

They're there for the changes round trips can't catch. A change made to the writer and the reader together, such as
the AAD layout, the key box layout, a renamed payload field or a change to the padding, still round-trips, while
every vault, note and backup saved before it stops opening. A fixture saved before it stops opening too, and its
test fails.

The backups have fixtures of their own, in
[`../../VaultBackupTests/Fixtures`](../../VaultBackupTests/Fixtures).

## The rule

**Never make a fixture again to get a test to pass.** A fixture test that fails means the app can no longer read
something an earlier version of it saved, which users have. Fix the reader.

**A format change adds a new fixture and keeps every old one.** Name the new one with the new version. The old ones
keep their tests for as long as the app might meet a file in that format, which for anything a user could have saved
is always.

## Adding a fixture

1. Define it next to the others, in the `GoldenFixtures` test file for its format: its name, with the format's
   version in it, its password, and what it holds, all as literal values.
2. Make it in [`GoldenFixtureRecorder`](../GoldenFixtures/GoldenFixtureRecorder.swift) with the app's own code, the
   way the app makes one, from that definition. Where the code takes its randomness from a parameter, such as a
   generator or a clock, the recorder can pass a fixed one. Where it doesn't, the recorder lets it choose, and prints
   whatever of that the tests check.
3. Record it on the Simulator. Test runs on the Simulator run on this Mac, so the recorder writes straight into this
   folder. It only makes fixtures that aren't here yet, and never replaces one.

   ```sh
   TEST_RUNNER_VAULT_RECORD_FIXTURES=1 xcodebuild test -workspace Vault.xcworkspace -scheme CI_iOS \
     -testPlan iOSAllTests -only-test-configuration Default -destination id=<simulator> \
     -only-testing:VaultFeedTests/GoldenFixtureRecorder
   ```

   `xcodebuild` passes `TEST_RUNNER_`-prefixed variables to the tests without the prefix. Nothing else sets
   `VAULT_RECORD_FIXTURES`, so the recorder is skipped in every other run.
4. Copy the values it printed into the definition, and write the tests. They read only the fixture and its
   definition, never the recorder.
5. Add it to the list below: what it is, how it was made, its password, and what it holds.

Keep fixtures cheap to read. A format that stores its key derivation's parameters, as the slot file's header does,
gets cheap ones, which is realistic, since the file carries whatever it was made with. One that names a derivation,
as encrypted items and backups do, uses the fast one debug builds use.

Keep them small, too. Store the bytes the format gives meaning to, and rebuild in the test what's only random, as the
slot file's unused slots are. Rebuild it at the same offsets, so the tests still open a whole file.

## Fixtures

All three were recorded on 28 September 2026 by `GoldenFixtureRecorder`, from `main` at `32f26d33`. Their formats
are the ones released in v2.0.0 (build 100012): nothing that writes or reads them has changed since that tag.

### `slot-file-v1-vault-slots.bin`

A whole encrypted vault file, `vault-slots.v1`, as a device has it after the App Lock Password is turned on and a
duress password added. It's format version 1, with 1 MiB slots, payload version 1 and LZFSE. Its header has Argon2id
parameters of 256 KiB, 3 passes and 1 lane, so a derivation takes about a millisecond.

**How it's stored.** The file is 16 MiB and its 128-byte header, but only two slots hold anything: the other
fourteen are random bytes. So the fixture stores the header, then slot 6, then slot 15, byte for byte as the recorder
made them: 2 MiB and 128 bytes. `SlotFileFixture.file()` rebuilds the whole file before any test opens it. It puts
the header first, then each slot at its offset, the stored ones at their own indices and every other one filled
with bytes from a seeded generator. The tests open that whole file, as the app would. Each box authenticates its slot's
index, so the stored slots only open at their own indices, and a test checks that swapped, they open nothing.

| Slot | Password | Holds |
| --- | --- | --- |
| 6 | `correct horse battery staple` | The real vault. |
| 15 | `café au lait`, with a composed `é` | The duress vault. |
| The other 14 | None | Random bytes. |

Any other password opens nothing. The tests try `Correct horse battery staple`, and the duress password with its
accent decomposed, which opens the duress vault, because a password derives from its composed form. They also
unlock the real vault through `VaultUnlockService` on a "device" that would calibrate other parameters, faster or
slower: it derives with the header's.

- **The real vault** was created as turning on the App Lock Password creates it (`VaultEncryptionConverter`), in
  slot 6, with its ten duress slots chosen at random. It holds:
  - a TOTP code and an HOTP code, one with a killphrase;
  - a Markdown note that's hidden until its search passphrase is typed, and locked;
  - the two encrypted items below, as they're stored;
  - two tags;
  - every backup setting: a backup password, the last backup, auto-backup to iCloud Drive with a file it wrote, and a
    PDF hint.
- **The duress vault** was made from the real vault by its store (`EncryptedVaultStore.makeDuressVault(password:)`),
  in the real vault's first duress slot, a day after the real vault. It was then given a TOTP code, a note and a tag
  by importing them, and a PDF hint. Both saves went through the store.

The items, tags and settings are `SlotFileFixture.real` and `SlotFileFixture.duress`. The salt, each key box's
generation and each vault's duress slots were chosen at random, and are recorded there too.

### `encrypted-note-v1.json`

An encrypted note as the app stores it: a vault payload, version 1, which is the JSON a slot holds before it's
compressed, with just that item in it. Its password is `open sesame`. It's `EncryptedItem` version 1.0.0, with its
key derived with `vault.keygen.item.fast.v1` and a random 48-byte salt, and a random 32-byte IV. It decrypts to the
Markdown note "Safe combination" (`EncryptedItemFixture.note`).

### `encrypted-recovery-phrase-v1.json`

A recovery phrase, which is always stored encrypted, in the same form, with the password `hunter2 hunter2`. It
decrypts to "Hardware wallet": BIP39's first test vector, twelve words with the passphrase `TREZOR`, which no one's
wallet uses (`EncryptedItemFixture.recoveryPhrase`).

Release builds derive item keys with `vault.keygen.item.secure.v1` rather than the fast derivation. That takes seconds
in a debug build, so the fixtures don't use it. `VaultKeyDeriverParameterPinTests` pins its parameters, and
`CryptoEngineTests` has known answers for the derivations it chains.
