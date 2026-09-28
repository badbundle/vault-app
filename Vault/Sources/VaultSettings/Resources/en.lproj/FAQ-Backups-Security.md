Backups are required to be encrypted with a password, which ensures that if a copy of your backup falls into the wrong hands, that person cannot access your data without the password.

## How does the encryption work?

When you enter an encryption password, it runs through a key derivation function (KDF) with some random salt that is used to generate a 256 bit key.
This key is then used with AES-GCM to perform a symmetric encryption of your vault.

The salt is chosen when you set the password, and every backup made with that password uses it.
So backups made with the same password can be told apart from ones made with another, though neither can be read.

This means the source of truth for the backup is the password that you choose, so you should make this as strong as possible.
The longer and more complex the better.

## What if my backup is leaked?

The KDF we use for backups in optimized builds of Vault is extremely strong, which is why it takes so long to generate your key initially (from several seconds to a few minutes, depending on your device).
This dramatically increases the cost for an attacker to bruteforce your password in the event that your backup document is leaked, because they will have to do this long generation for every bruteforce attempt.

Once you have chosen a sufficiently secure password, it should be infeasible that an attacker will be able to bruteforce your password within your lifetime (assuming the underlying encryption algorithms are not broken).

Please follow best-practices for creating strong passwords when choosing a backup password, it is the single point of failure for the security of your backups.
Vault asks for at least 8 characters, and not only numbers, but that's a minimum: it should be of similar complexity to a master password for a password manager.

## What else is in a backup?

Everything in your vault, and the keys Vault checks killphrases and search passphrases with, so they still work once the backup is restored.
That means someone who knows a backup's password could also try guesses at its killphrases and passphrases, so don't use a password from anywhere else as one.
