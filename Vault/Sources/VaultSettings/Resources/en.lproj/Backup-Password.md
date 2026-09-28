Every backup Vault creates is encrypted with your backup password. Without it, nobody can read what's inside a backup — including you.

## What happens when I set a password?

Your password is turned into an encryption key on this device, and Vault keeps that key so it can make backups without asking for your password each time. **The password itself is never stored.**

Without an App Lock Password, the key is in the device's keychain, protected by Face ID, Touch ID or your passcode. With one, it's inside your encrypted vault, and a duress vault has its own.

Preparing the key is deliberately slow: it can take up to 3 minutes, even on a fast device.
Anyone trying to guess your password from a leaked backup has to go through the same slow step for every single guess, which makes guessing a strong password impractical.

## Is my password shared with my other devices?

No. The key isn't synced to your other devices. Each device you make backups from has its own backup password, and they don't have to match.

To restore a backup, on this device or another, you enter the password that backup was made with, and Vault prepares the key from it. Vault asks for it every time, even for a backup made with the password set now: the key it keeps is only used to make backups, never to open them.

## Choosing a password

Your password is the only thing protecting your backups, so treat it like the master password for a password manager: long, unique and not used anywhere else.
A few random words strung together make a good start.

Like the App Lock Password, it has to be at least 8 characters, and not only numbers. A password you set before this was required keeps working.

## What if I forget it?

There is **no way to recover** a forgotten backup password, and backups made with it can't be restored without it.

If you forget your password but still have this device, set a new one and create a fresh backup straight away.
