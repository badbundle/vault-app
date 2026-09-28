# Backup corpus

A backup in every format the app still has to restore, each made once and kept exactly as it was made. The tests in
[`../../GoldenFixtures`](../../GoldenFixtures) restore every one as the Backups page does: the PDF into the import
flow, its password into the password screen, and what it decrypts into a vault. Each must give back exactly the vault
it was made of, as its format carried it: the same items, tags, killphrases, search passphrases and lock states.

The same rule as the other golden fixtures applies (see [`../README.md`](../README.md)): **never make a backup here
again to get a test to pass**, and **a format change adds a new backup and keeps every old one**. People restore
backups years after they made them, some from paper.

## The vault

Every backup is of the same vault, `BackupCorpus` in
[`BackupCorpus.swift`](../../GoldenFixtures/BackupCorpus.swift):

- a TOTP code, which isn't offered in QuickType, with a tag and a colour;
- an HOTP code with a killphrase, `kill me`;
- a locked Markdown note, hidden until its search passphrase, `find me`, is typed, and whose preview is hidden;
- the encrypted note and the recovery phrase from [`../README.md`](../README.md), as they're stored, which their own
  passwords, `open sesame` and `hunter2 hunter2`, still open once restored;
- two tags.

The killphrase and search passphrase digests were made with the keys of the device that made the backups: 32 bytes of
`0xA1` and of `0xA2`. Restored with those keys, the phrases work. On another device, whose keys differ, the backups
still import, and the digests arrive exactly as they were.

**Every backup's password is `correct horse battery staple`.** Its key is derived with `vault.keygen.backup.fast.v1`,
as debug builds derive it, which takes milliseconds. Release builds derive with `vault.keygen.backup.secure.v1`, which
takes minutes without optimization; `VaultKeyDeriverParameterPinTests` pins its parameters. Each backup's salt and IV
were random, and each carries them.

## The backups

All were recorded on 28 September 2026 by
[`BackupCorpusRecorder`](../../GoldenFixtures/BackupCorpusRecorder.swift), from `devops/restore-corpus`, whose backup
code is `main`'s at `32f26d33`. That's the backup code released in v2.0.0 (build 100012). The release tags from
v2.0.0 (build 100007) on differ in two ways only, both in what's inside the encryption: #624 added each item's
QuickType and preview choices, and VAULT-75 padded saved backups to a fixed size. The PDF around a backup, and the QR
codes, haven't changed in a way a restore reads since long before, so every format that differs was made with today's
code, as described for each, rather than by building an old tag.

| File | Format | Padding | Size |
| --- | --- | --- | ---: |
| `auto-backup.json` | Today's | 32 KiB | 44 KB |
| `pdf-random-padding.pdf` | Today's | Random | 150 KB |
| `transfer-qr-codes.json` | Today's | Random | 6 KB |
| `pdf-before-quicktype-and-preview.pdf` | Before #624 | Random | 218 KB |
| `pdf-plaintext-search-passphrase.pdf` | Before #519 | Random | 179 KB |

### `auto-backup.json`

An auto-backup as `AutoBackupServiceImpl` writes one into its folder, made by the service itself, padded to just under
32 KiB of ciphertext (32,764 bytes), as saved backups have been since VAULT-75.

The corpus keeps the backup the auto-backup's PDF carries rather than the PDF: the `EncryptedVault` exactly as the PDF
holds it, which is how `EncryptedVaultCoder` encodes it. A PDF around a backup padded to 32 KiB is about a megabyte,
most of it the images of its 90 or so QR codes, which a restore doesn't read, and the other PDFs here cover reading a
backup out of one. So the tests hand it to the import flow where the flow has read it out of the PDF
(`handleImport(fromEncryptedVault:)`), then enter its password, and it restores to exactly the vault.

It stands for the PDFs the Backups page has saved since VAULT-75 too. Their backups are the same: the PDFs differ only
in the title and hint printed on them.

### `pdf-random-padding.pdf`

A PDF backup as the Backups page saved one from #624 until VAULT-75: v2.0.0 builds 100008 to 100011. Made with the
page's steps as they were then, which are today's with random padding: `EncryptedVaultEncoder(padding: .random)`,
which a device transfer still uses, and the same PDF. 3,216 bytes of ciphertext. It restores to exactly the vault.

### `transfer-qr-codes.json`

The QR codes a device transfer shows, made by `DeviceTransferExportViewModel` itself, each read back from the image the
transfer screen shows, as a camera would read it: a JSON array of each code's text, in the order they're shown.
Padded by a random amount, to 2,832 bytes of ciphertext. Scanned in any order, with repeats and a code from another transfer, it restores to
exactly the vault.

### `pdf-before-quicktype-and-preview.pdf`

A PDF backup as the Backups page saved one before #624: v2.0.0 build 100007 and earlier, back to #519. Its items
don't record whether each code is offered in QuickType or how much of each note the feed shows. It was made with
today's steps, with those two left out of every item, and random padding: 5,160 bytes of ciphertext. They're optional fields, and a backup leaves
out a field that isn't set, so the payload is what those builds wrote. It restores to the vault with every code
offered in QuickType and every note previewing its title and first line, as those builds' backups always have.

### `pdf-plaintext-search-passphrase.pdf`

A PDF backup as the Backups page saved one before #519, which kept each search passphrase in plain text. It was made
by hand, as that release's code wrote one: the items as its `VaultBackupItemEncoder` wrote them (`LegacyBackupItem` in
the recorder, from `VaultBackupPayload.swift` at `5ebe6b83`), encoded, compressed and sealed as its backup steps did,
which are today's, with random padding, in today's PDF: 4,076 bytes of ciphertext. It doesn't record QuickType or preview choices either.

Restoring it drops each plain-text search passphrase, as it has since #519: the note keeps its visibility, but no
passphrase finds it. Otherwise it restores to exactly the vault, with every code offered in QuickType and every note
previewing its title and first line.

## Adding a backup

When a backup format changes, or the way the app saves or restores one does:

1. Add a `BackupCorpusEntry` for it, named for its format, with what restoring it should give (`Format`) and its
   padding.
2. Make it in [`BackupCorpusRecorder`](../../GoldenFixtures/BackupCorpusRecorder.swift), with the app's own code, the
   way the app saved one. For an older format that today's code can't write, write it by hand from that release's
   encoder, and say so here.
3. Record it on the Simulator, as for the other golden fixtures:

   ```sh
   TEST_RUNNER_VAULT_RECORD_FIXTURES=1 xcodebuild test -workspace Vault.xcworkspace -scheme CI_iOS \
     -testPlan iOSAllTests -only-test-configuration Default -destination id=<simulator> \
     -only-testing:VaultFeedTests/BackupCorpusRecorder
   ```

4. Copy the ciphertext length it printed into the entry, add it to `BackupCorpusEntry.backups` if it's restored from a
   file, and add it to the list above. Keep each backup small: KBs, or a few hundred of them at most. A backup padded
   to a fixed size is kept as the `EncryptedVault` its PDF carries, as the auto-backup is.
