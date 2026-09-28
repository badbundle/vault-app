# Golden fixtures

Backups as the app saves them, each made once by the app's own code and kept exactly as it was made. The tests in
[`../GoldenFixtures`](../GoldenFixtures) open every one and check it holds what it was made with.

They're there for the changes round trips can't catch. A change made to the encryptor and the decryptor together,
such as a renamed field in an item, still round-trips, and passes the known answer for an empty backup, while every
backup saved before it stops restoring. A fixture saved before it stops restoring too, and its test fails.

The encrypted vault file and encrypted items have fixtures of their own, in
[`../../VaultFeedTests/Fixtures`](../../VaultFeedTests/Fixtures). Whole PDFs and their QR codes are VAULT-87's.

## The rule

**Never make a fixture again to get a test to pass.** A fixture test that fails means the app can no longer restore a
backup an earlier version of it saved, which users have, perhaps only on paper. Fix the reader.

**A format change adds a new fixture and keeps every old one.** Name the new one with the new version. The old ones
keep their tests for as long as the app can restore a backup in that format, which is always.

Each fixture's tests also check that the encryptor, given the fixture's salt, IV and padding, writes the fixture
again byte for byte. That's a known answer for the writer, not the reader, so only the newest fixture of each kind
keeps it: when what's written changes, move the check to the new fixture, and keep the old one's reading tests.

## Adding a fixture

1. Define it in [`BackupFixtureTests.swift`](../GoldenFixtures/BackupFixtureTests.swift): its name, with the format's
   version in it, and anything about it that differs from the others. The backup inside, its password and its items,
   is `BackupFixture`'s, as literal values.
2. Make it in [`BackupFixtureRecorder`](../GoldenFixtures/BackupFixtureRecorder.swift) with the app's own code, the way
   the app saves a backup. The code chooses the salt, the IV and the padding at random. The fixture carries the salt
   and the IV, and the padding is inside what it encrypts, so the recorder prints only the ciphertext's length.
3. Record it on the Simulator. Test runs on the Simulator run on this Mac, so the recorder writes straight into this
   folder. It only makes fixtures that aren't here yet, and never replaces one.

   ```sh
   TEST_RUNNER_VAULT_RECORD_FIXTURES=1 xcodebuild test -workspace Vault.xcworkspace -scheme CI_iOS \
     -testPlan iOSAllTests -only-test-configuration Default -destination id=<simulator> \
     -only-testing:VaultBackupTests/BackupFixtureRecorder
   ```

   `xcodebuild` passes `TEST_RUNNER_`-prefixed variables to the tests without the prefix. Nothing else sets
   `VAULT_RECORD_FIXTURES`, so the recorder is skipped in every other run.
4. Copy the length it printed into the definition, and add the fixture to `BackupFixture.all`. Its tests read only the
   fixture and its definition, never the recorder.
5. Add it to the list below: what it is, how it was made, its password, and what it holds.

## Fixtures

Both were recorded on 28 September 2026 by `BackupFixtureRecorder`, from `main` at `32f26d33`. The backup format is
the one released in v2.0.0 (build 100012): nothing that writes or reads it has changed since that tag.

Each is an `EncryptedVault`, version 1.0.0, as `EncryptedVaultCoder` encodes it: the JSON a PDF or an auto-backup
carries, before a PDF splits it into QR codes. Its password is `correct horse battery staple`, and its key is derived
with `vault.keygen.backup.fast.v1`, with a random 48-byte salt, and a random 32-byte IV. Both hold the same backup
(`BackupFixture`), "Before the trip", of a vault with:

- a TOTP code and an HOTP code, one with a killphrase;
- a Markdown note that's hidden until its search passphrase is typed, and locked;
- an encrypted note, which a backup carries as it's stored;
- two tags.

Release builds derive backup keys with `vault.keygen.backup.secure.v1` rather than the fast derivation. That takes
minutes in a debug build, so the fixtures don't use it. `VaultKeyDeriverParameterPinTests` pins its parameters, and
`CryptoEngineTests` has known answers for the derivations it chains.

### `backup-v1-padded-to-32-kib.json`

Padded as saved backups have been since VAULT-75 (`76f03c5f`): with random bytes in the payload's
`obfuscationPadding`, inside the encryption, until what's encrypted is just under 32 KiB: 32,764 bytes of
ciphertext.

### `backup-v1-random-padding.json`

Padded as every backup was before VAULT-75, and as a device transfer still is: with a random amount of random bytes,
here making 2,420 bytes of ciphertext. It was made with today's `.random` padding, which is the code every backup used
before VAULT-75: that change only added the fixed size, and chose it for saved backups. Backups from v2.0.0 (build
100011) and earlier were padded this way.
