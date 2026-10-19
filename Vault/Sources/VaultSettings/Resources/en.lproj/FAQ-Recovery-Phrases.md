A recovery phrase, also called seed words or a seed phrase, is the list of words that restores a crypto wallet. Anyone who has it can do what you can with the wallet, so Vault keeps one as carefully as anything it holds.

## How is a recovery phrase protected?

- It's **always encrypted** with a password of its own, which Vault never stores, and **always locked** with Face ID, Touch ID or your passcode. On a Mac, it's Touch ID or your Mac's password. Neither can be turned off.
- Once it's open, the words stay **masked until you tap them**.
- They're **hidden** while Vault isn't in the foreground, so they don't show in the app switcher, and while your screen is being recorded, mirrored or shared.
- They **can't be copied**: not from the item, and not from the editor while you type them. To use the phrase in a wallet, reveal the words and type them in there.

Vault can't block a screenshot on an iPhone or iPad, so reveal the words only when no one else can see your screen.

The title isn't encrypted, so the item shows in your vault and search finds it by its title. Avoid naming the wallet in it. The description is encrypted with the words.

Killphrases, search passphrases and tags work for a recovery phrase as they do for any other item, and backups and transfers carry it encrypted, as they carry everything else.

## Why are the words masked, and why can't I copy them?

Words showing on a screen can be read by anyone looking at it, so they're hidden until you choose to show them, and again when Vault goes to the background.

Copied text goes onto the clipboard, where other apps may be able to read it and, with Universal Clipboard, other devices may receive it. A phrase that can't be copied can't end up there. Typing the words into your wallet keeps them off the clipboard.

## What does Vault check?

Choose the kind of phrase you have, and Vault checks its words and checksum as you type or paste them, marking any word that isn't in the wordlist:

- **BIP39**, which most wallets use, with 12, 15, 18, 21 or 24 words, in any of its 10 languages.
- **SLIP-39**, a single share of the backup a Trezor makes, with 20 or 33 words.
- **Electrum** seeds.
- **Monero** seeds, with 25 words in English.
- **Other**, for any other list of up to 48 words, which Vault keeps as you entered it without checking it.

A phrase that doesn't check is still saved, with a warning, so a phrase you need is never turned away. A warning usually means a mistyped word, or words in the wrong order.

## What about a passphrase?

Many wallets let you add a passphrase to a phrase, sometimes called the "25th word". Vault keeps it with the words, encrypted with them. It's kept exactly as you enter it, because any change to it, even a space, is a different wallet. Vault warns when a passphrase starts or ends with a space, and when a SLIP-39 passphrase uses characters that standard doesn't allow.

## How do I back up a recovery phrase?

Vault is another safe place for your phrase, not a replacement for the paper or metal copy your wallet had you make. Keep that copy somewhere safe too.

A backup made by Vault is a PDF that you can save or print for a paper copy. A recovery phrase in it is encrypted with the backup's password, and still with its own password, so reading it takes both. The FAQ about backups explains how they work. Keep at least one somewhere other than this device.

## What if I forget the password?

There's no way to recover it. Like any item encrypted with its own password, a recovery phrase whose password is lost can't be opened, even by you. Choose a long password, such as a few random words, and keep a backup of the phrase somewhere safe.
