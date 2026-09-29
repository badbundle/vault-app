# Export compliance

Every build tells App Store Connect whether Vault uses encryption that needs export compliance documentation, for
US export rules and the import rules of the countries it's sold in. Vault says it doesn't:
`ITSAppUsesNonExemptEncryption` is `NO`, set in the app's Xcode project as
`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`. This says why that's right, and what keeps it right.

This was researched in September 2026 (VAULT-99). It isn't legal advice.

## The rule

**All of Vault's encryption uses Apple's CryptoKit.** Anything that hides data so that it can be decrypted later,
such as an item, a backup or the vault file, is encrypted with `AES.GCM` from CryptoKit. Don't encrypt with an
algorithm from another library, or one of our own. If Vault ever needs one, see [If that changes](#if-that-changes).

## Why `NO` is right

Apple puts an app's encryption in one of three tiers
([Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)):

| The app's encryption | Documentation Apple asks for |
| --- | --- |
| Limited to that within the Apple operating system | None |
| An industry standard algorithm, not provided within the Apple operating system | A French encryption declaration, if the app is sold in France |
| Proprietary algorithms not accepted by international standard bodies | A US classification (CCATS) and a French encryption declaration |

`NO` means the app "only uses forms of encryption that are exempt from export compliance documentation
requirements", in the words of
[Apple's documentation for the key](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).
Vault's encryption is all in the first tier.

What Vault uses, and whether it's encryption:

| What | Implementation | Encryption? |
| --- | --- | --- |
| AES-GCM for the vault file, encrypted items, recovery phrases, backups and transfers | CryptoKit | Yes, Apple's |
| The keychain and iOS Data Protection | iOS | Yes, Apple's |
| scrypt, PBKDF2 and HKDF, which turn a password into a key | CryptoSwift | No: key derivation is one-way and can't decrypt anything |
| Argon2id, which turns the App Lock Password into a key | `CArgon2`, the reference C implementation | No, as above |
| HMAC for HOTP and TOTP codes | CryptoSwift | No: that's authentication |
| SHA digests | CryptoSwift | No: that's data integrity |
| HMAC-SHA256 digests of killphrases and search passphrases, and recovery phrase checksums | CryptoKit | No, and Apple's anyway |

scrypt uses the Salsa20/8 core, but as a mixing step inside a one-way function
([RFC 7914](https://www.rfc-editor.org/rfc/rfc7914)), never to encrypt data. The US definition of cryptography
for data confidentiality leaves out authentication, digital signatures and data integrity
([BIS](https://www.bis.gov/learn-support/encryption-controls/cryptography-for-data-confidentiality)).

scrypt and Argon2 have no implementation in Apple's operating system, and they can't be replaced: backups and vaults
made with them have to keep opening (G67 in [`security-model.md`](./security-model.md)).

## What the library doesn't change

Moving AES-GCM from CryptoSwift to CryptoKit changed which of Apple's documentation tiers Vault is in. It didn't
change what the law makes of Vault: it's the same algorithm, used for the same thing.

- **United States.** Vault is mass-market encryption software, whichever library does the encrypting. Since the
  Bureau of Industry and Security's rule of March 2021, a mass-market consumer app needs no annual self-classification
  report. Only chips, components and their executable software still do
  ([summary](https://www.kelleydrye.com/viewpoints/blogs/trade-and-manufacturing-monitor/bis-eliminates-most-reporting-requirements-for-open-source-and-mass-market-encryption/)).
  Published open-source code that uses standard cryptography is released from the rules too. So there's nothing to
  file in the US.
- **France.** French law defines a cryptology means by what it does, so an app that encrypts its users' data is
  arguably one, whoever wrote the AES. Apple only asks for the French declaration from apps that bring their own
  encryption, as Vault no longer does. That's Apple's line, not a ruling from ANSSI. The one way to be fully covered
  in France, whatever the library, is to file a declaration with ANSSI: it's free, it's made by email, and it's
  decided within one to two months
  ([ANSSI](https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/)).
  Vault hasn't filed one.

## If that changes

If Vault ever needs encryption that CryptoKit doesn't provide:

1. Set `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` to `YES` in both of the app's build configurations.
2. File the French declaration with ANSSI, and upload it in App Store Connect once it's approved. Until then, take
   Vault off sale in France.
3. Update this file.

## History

Until VAULT-99 (September 2026), encrypted items, recovery phrases and backups used CryptoSwift's AES-GCM, so the
`NO` in builds up to 100014 wasn't accurate. None of those builds was released on the App Store. The change kept the
format exactly, with the same keys, 32-byte IVs and 16-byte tags, and every test passed unchanged. Everything
encrypted before it opens as it always has.
