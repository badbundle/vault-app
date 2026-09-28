Vault does **not** automatically sync your items between devices, and this is by design.
Keeping your data on a single device, under your control, is what allows Vault to make the privacy guarantees it does — nothing is ever uploaded to a server, and there is no account to compromise.

To move items to another device, you create a backup on one device and restore it on the other.

## Moving everything to a new device

1. On your current device, create a backup from the Backups screen and choose a strong password.
2. Get that backup file onto your new device. A few options:
    - Save it to **iCloud Drive** (or any other cloud storage you trust) and open it on the new device via the Files app.
    - Send it to yourself via **AirDrop**.
    - Print the backup as a paper copy and **scan the QR code** on the new device.
3. On the new device, open the backup from the Backups screen and enter the password you chose. Use **Import & Override** to replace anything already there with the backup's contents.

## Do killphrases and passphrases still work after restoring?

Yes, for backups made with this version of Vault or later. A backup carries the keys Vault checks killphrases and search passphrases with, inside its encryption, so they keep working on the device you restore it to, and on this one after it's been erased.

A backup made with an earlier version doesn't carry them. Restored on another device, or after an erase, its killphrases won't delete anything, and items that only show for their passphrase can't be found. If the device that made it still has its vault, make a new backup there and restore that one instead.

## Can I automate this with iCloud Drive?

Partially. Vault supports **automatic backups to iCloud Drive** — you point Vault at a folder in your iCloud Drive once, and it will keep a fresh backup there for you.

This is **not sync**. It's still a backup-and-restore flow: your other device sees the backup file appear in iCloud Drive, and you import it from there. Items don't appear automatically and edits don't propagate.

For most people this is still more friction than it's worth — it's usually easier to pick one device as the "primary" and keep the other as a backup destination only. But if you do want the two devices to stay roughly in step, auto-backup to iCloud Drive plus **Import & Merge** on the other device is the closest you can get. Merging keeps the most recent edit for each item, so it's safe in both directions.

## Why isn't there a true sync option?

True sync would mean either uploading your data to a server (even encrypted, this introduces a new attack surface and a new account for you to manage) or relying on a system like iCloud's CloudKit to silently move your data between devices.

Vault deliberately avoids both. The backup-and-restore flow — even when iCloud Drive is doing the heavy lifting — keeps you in full control of when and where your data moves.
