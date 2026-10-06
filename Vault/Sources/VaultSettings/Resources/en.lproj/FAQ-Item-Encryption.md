Without an App Lock Password, items in your vault are stored on this device without an additional layer of encryption — they are protected by the security of the device itself. An App Lock Password encrypts the whole vault.

If you want extra protection for sensitive items, Vault lets you encrypt individual items with a password of your choice. This is independent from your backup password and from any other items in your vault.

## How does the encryption work?

When you set an encryption password on an item, it runs through a key derivation function (KDF) with some random salt that is used to generate a 256 bit key.
This key is then used with AES-GCM to perform a symmetric encryption of that item's contents.

The item's title, description and tags aren't encrypted, so the item still shows in the feed and can be found by its title. A recovery phrase's description is encrypted with its words.

The password is **never stored** anywhere on the device. Each time you want to view the item, you'll be asked to enter the password so the key can be re-derived and the contents decrypted in memory.

This means the source of truth for an encrypted item is the password that you choose, so you should make this as strong as possible.
The key derivation for items is lighter than the App Lock Password's, so that items open quickly. That makes a long password all the more important: a few random words are a good start.

## What if I forget the password?

There is no recovery mechanism. If you forget the password for an encrypted item, that item is **permanently inaccessible** — not even you can recover it.

This is the trade-off for strong encryption: it protects your data from everyone, including you, if the password is lost.

## Is this the same as locking an item with Face ID or Touch ID?

No — these are two separate features that can be used together.

- **Per-item encryption** (this page) encrypts the item's contents with a password you choose. Without the password, the data cannot be read by anything.
- **Per-item lock** uses your device's native security (Face ID, Touch ID, or the device's passcode or password) to gate access to the item in the app. The data itself is not re-encrypted — the device's own protections are used to keep it out of view.

Use per-item encryption for an extra layer on your most sensitive items, with a long password. Use a per-item lock when you just want a quick prompt before viewing.
