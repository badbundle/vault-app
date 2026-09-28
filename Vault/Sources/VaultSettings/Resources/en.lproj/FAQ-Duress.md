A duress password opens a separate vault instead of your real one. If someone makes you unlock Vault, you can give them the duress password, and they see that vault, not your real one.

To set one, turn on the App Lock Password in Settings, open it, choose **Set Duress Password**, and enter the password you unlocked Vault with, along with the new duress password.

Use a duress password you've never used in Vault. If it happens to open another vault too, the new, empty vault opens instead, and that other vault can't be opened any more.

## Can anyone tell there's another vault?

Not from Vault itself. Every vault is kept in the same file, which always has room for sixteen whether you use one or several, and unlocking takes the same time whichever password you enter.

Some things can still give it away:

- **An empty or brand new duress vault.** Items show when they were added, so a vault filled today looks new. Put some codes and notes in it early, and open it now and then, so it looks used.
- **Your real vault's backups.** Backups saved on this iPhone, or in a folder it can reach, can be found, and the duress vault's backup password won't open them. Keep your real vault's backups somewhere else, and give the duress vault its own backup password, backups and auto-backup folder.
- **The folder picker.** When you choose an auto-backup folder, it opens where it was last used, which may be your real vault's folder.
- **Older copies of this iPhone's data,** such as an earlier iCloud or computer backup, compared with the vault as it is now.

## Can I have more than one?

Each vault has one duress vault: setting a new duress password replaces the one before. A duress vault can have its own duress vault, set up the same way from inside it, so you can have several, one after another, each with its own password.

Your real vault is never touched by duress vaults up to eleven deep. Beyond that, a new duress vault could take your real vault's place, so don't go deeper than that.

## What happens after wrong passwords?

Vault makes you wait longer after each wrong App Lock Password, and if you turn on **Erase Vault After 10 Failed Passwords**, it erases every vault after 10 wrong ones in a row.

Any vault's password, your real one or a duress one, starts the count towards erasing again, and can turn erasing off for this iPhone. The waits don't start again: they keep growing with each wrong password, whichever vault opens in between, and only get shorter with time, by one wrong password for every hour that passes.

So someone who has your duress password is held back by the waits, not by erasing. What keeps your real vault safe is a long App Lock Password that nobody can guess.

## How do I start a duress vault again?

Unlock the vault above it, your real vault for the first one, and set a new duress password. It replaces the old duress vault, and the new one starts empty.

Don't use **Delete All Data** for this. It deletes every vault on this iPhone, your real one included, whichever vault you're in.

## What about killphrases?

A killphrase deletes an item, quietly, when you search for it in Vault. You set one on the item's edit screen, and it works with or without a duress password.

- It deletes the item as soon as the search is exactly the phrase, even partway through typing something longer. Capitals count, and spaces at either end don't. Choose a phrase you'd never type on the way to another search.
- It only works in Vault's own search, not in AutoFill's.
- It deletes the item from this vault. Backups made before then still have it, as **About Backups** explains.
