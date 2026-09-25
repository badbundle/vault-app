Every backup Vault creates is encrypted with your backup password. Without it, nobody can read what's inside a backup — including you.

## What happens when I set a password?

Your password is turned into an encryption key on this device. Vault keeps that key in the device's keychain, protected by Face ID, Touch ID or your passcode. **The password itself is never stored.**

Preparing the key is deliberately slow: it can take up to 3 minutes, even on a fast device.
Anyone trying to guess your password from a leaked backup has to go through the same slow step for every single guess, which makes guessing a strong password impractical.

## Is my password shared with my other devices?

No. The key stays on this device and isn't synced anywhere. Each device you make backups from has its own backup password, and they don't have to match.

To restore a backup on another device, you enter the password that backup was made with, and Vault prepares the key there.

## Choosing a password

Your password is the only thing protecting your backups, so treat it like the master password for a password manager: long, unique and not used anywhere else.
A few random words strung together make a good start.

## What if I forget it?

There is **no way to recover** a forgotten backup password, and backups made with it can't be restored without it.

If you forget your password but still have this device, set a new one and create a fresh backup straight away.
