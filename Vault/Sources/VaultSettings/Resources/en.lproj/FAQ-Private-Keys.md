A private key is the secret that controls a crypto wallet, signs as you with PGP, or logs you in with SSH. Anyone who has it can do what you can with it, so Vault keeps one as carefully as it keeps a recovery phrase.

## How is a private key protected?

- It's **always encrypted** with a password of its own, which Vault never stores, and **always locked** with Face ID, Touch ID or your passcode. On a Mac, it's Touch ID or your Mac's password. Neither can be turned off.
- Once it's open, the key stays **masked until you tap it**, and it's masked again when the item closes or locks.
- It's **hidden** while Vault isn't in the foreground, so it doesn't show in the app switcher, and while your screen is being recorded, mirrored or shared.
- It **can't be copied**: not from the item, and not from the editor while you type it. To use the key in a wallet, reveal it and type it in there.
- Vault doesn't show it as a QR code, which anyone with a camera could take.

The title isn't encrypted, so the item shows in your vault and search finds it by its title. Avoid naming the wallet or what the key unlocks in it. The description is encrypted with the key.

Killphrases, search passphrases and tags work for a private key as they do for any other item, and backups and transfers carry it encrypted, as they carry everything else.

## What kinds of keys can I keep?

Vault recognizes these, and checks each one as you type or paste it:

- **WIF** keys, as Bitcoin wallets export a single key, with their checksum, network and whether they're compressed.
- **Extended private keys**: xprv, and the yprv, zprv, tprv and other versions wallets use, with their checksum.
- **Raw hex** keys, 64 hexadecimal digits, with or without `0x`.
- **Nostr** keys that start with `nsec`, with their checksum.
- **OpenPGP** private key blocks, with the armor's checksum when it has one.
- **OpenSSH** private keys, as `ssh-keygen` writes them, and **PEM** private keys: RSA, EC, DSA and PKCS #8.

A key that doesn't check is still saved, with a warning, so a key you need is never turned away. Vault also warns when what you've entered is a public key, which is easy to copy by mistake. Anything else you enter is kept exactly as you entered it, as **Other**.

## Does Vault work anything out from my key?

No. Vault never works out a public key or an address from it, never signs anything with it, and never sends it anywhere: it only says what the key looks like from its own text.

## What if I forget the password?

There's no way to recover it. Like any item encrypted with its own password, a private key whose password is lost can't be opened, even by you. Choose a long password, such as a few random words, and keep a backup of the key somewhere safe.
