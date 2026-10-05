# Release Playbook

Tags are the permanent release record. Release branches are maintenance lines
for supported versions, not the historical archive.

## Branch model

- Ship from `main`: build the commit to release, upload it, then tag that same
  commit.
- Tag every shipped build, including the App Store build number, for example
  `v2.0.0+100123`. The tags say which commit became which build, so nothing
  else needs to.
- Don't keep a branch per version, and don't move a release branch along
  `main` after each build. It says nothing the tags don't, and it goes stale.
- Create `release/2.0` only when a `2.0.x` fix has to ship while `main` holds
  unreleased work for the next version. Branch it from the last `v2.0.0+…`
  tag, not from `main`; see
  [Starting a maintenance branch](#starting-a-maintenance-branch).
- Use `release/2.0` only for `2.0.x` stabilization and hotfix work.
- When a hotfix ships from a release branch, merge or cherry-pick the relevant
  fix back to `main` when it still applies.
- Delete the branch once that version gets no more fixes. Its builds stay
  tagged.

## Build numbers

Build numbers are global across all versions and branches. They identify App
Store artifacts, not a marketing-version sequence.

- Fastlane queries App Store Connect/TestFlight at release time and builds with
  the build after the latest upload.
- `CURRENT_PROJECT_VERSION` in Git is a floor, not a record of the last build.
  A floor above the next build is used as it is, so raising it skips ahead to
  that number and never past it.
- Do not commit build-number bumps, before a release or after one. The lane
  passes the number to `xcodebuild`, so a bump never reaches the binary, and
  the tag already records it. A build made locally shows the floor, which is
  fine.
- It is fine for `release/2.0` to ship a build number higher than a later
  marketing version if that is the next global App Store build number.

To inspect the next build number without changing project files:

```sh
bundle exec fastlane increment_build
```

## Checking a build on a device

The unit tests stand in for Face ID and the passcode, and the simulator has
neither, so the app's use of the real ones is checked by hand, on an iPhone
with Face ID and a passcode, before each release. With App Lock on and an App
Lock Password set:

- Launch: Face ID is asked for by itself, then the password. The vault opens
  with the password.
- Cancel the Face ID prompt: the lock screen stays, with Unlock to try again.
- Look away until Face ID fails, then use the passcode instead: the password is
  asked for next.
- Lock the device with the app open, then unlock the device: Vault is locked,
  and asks for Face ID and the password again, whatever Require Unlock says.
- Open the AutoFill sheet from a one-time code field: it asks for Face ID, then
  the password, and fills the code.
- Turn off the device passcode (Settings, Face ID & Passcode): Vault's lock
  screen says to set one up, and never shows the password field. Turn the
  passcode back on: Face ID, then the password, open the vault again.

## Checking a build on a Mac

The Mac app's use of the real Touch ID, screen capture and AutoFill is checked
by hand, on a Mac with Touch ID, before each release of the Mac app, and on
each new version of macOS.

**Capture.** With Hide While Recording on, take a screenshot (⇧⌘3), a screen
recording (⇧⌘5), a screen share (FaceTime or another app) and an AirPlay
mirror, each with these on screen in turn: the main window with a code's page,
an editor sheet, an alert, Settings, the QR code scanner and the AutoFill
sheet. None of them is in any capture. Turn Hide While Recording off: they all
are.

**Locking.**

- With Settings open, close the main window, then choose Window, Vault: it's
  locked.
- Minimise the main window with an item open: the Dock's image of it shows
  nothing from the vault, and it's locked when it's back.
- Copy a code, then lock the Mac: the clipboard is empty once it's unlocked.
- With Spotlight's clipboard history on, copy a code: it isn't in the history.

**AutoFill.** In System Settings, General, AutoFill & Passwords, turn on
Vault, then in Safari, on a page with a one-time code field:

- Choose Vault in the field's AutoFill menu: its sheet asks for Touch ID, then
  the App Lock Password, and lists the vault's time-based codes.
- Search, and choose a code: it fills the field, and the sheet goes.
- Open the sheet again: it asks for Touch ID and the password again.
- A locked code, or one hidden behind a search passphrase, isn't listed, and
  searching for a killphrase deletes nothing.
- With the sheet unlocked, go to another app and back: the sheet is locked.
- Lock the Mac with the sheet open, then unlock it: the sheet is locked.

## Shipping a build

Run the release lane only when you intend to build and upload a real App Store
build:

```sh
bundle exec fastlane ios release
```

The release lane:

- requires a clean Git working tree
- queries App Store Connect/TestFlight for the latest uploaded build number
- builds with `CURRENT_PROJECT_VERSION=<next global build number>`
- uploads the build to App Store Connect, with the listing in
  `fastlane/metadata/` and the screenshots in `fastlane/screenshots/en-US/`;
  the screenshots replace the version's, so one that changed, was renamed or
  was removed doesn't stay behind in App Store Connect
- does not commit build-number changes
- does not create or push Git tags

Every build tells App Store Connect that Vault uses no encryption needing export
compliance documentation (`ITSAppUsesNonExemptEncryption` is `NO`), so there's
no export question to answer. That holds only while all of Vault's encryption
is Apple's CryptoKit: [`docs/export-compliance.md`](docs/export-compliance.md)
says why, and what to do if that changes.

Record the build number printed by the release lane, for example:

```text
Using release build number 100123
```

If the build succeeded but upload failed, retry the existing IPA upload:

```sh
bundle exec fastlane ios upload
```

The upload lane does not build, bump, commit, or tag anything.

## Updating the screenshots

`make screenshots` in `Vault/` makes the App Store screenshots (see
[`Vault/Screenshots/README.md`](Vault/Screenshots/README.md)), and the next
release uploads them. To put them on the App Store without a release, once
they're merged:

```sh
bundle exec fastlane ios upload_screenshots
```

It replaces the screenshots of the version App Store Connect is editing with
exactly those in `fastlane/screenshots/en-US/`, as the release lane does. It
doesn't build, upload a binary, change the listing's text or submit anything.

## Updating the listing

The listing's text is in `fastlane/metadata/`: the name, subtitle and keywords
(the only fields App Store search reads), the description, the promotional
text and the URLs in `en-US/`, and the notes for App Review in
`review_information/`. The App Privacy answers are in
`fastlane/app_privacy_details.json`. The release lane uploads the text with
every build. To upload it, and publish the privacy answers, without a build:

```sh
bundle exec fastlane ios upload_metadata
```

It changes the version App Store Connect is editing. It doesn't build, upload
a binary or screenshots, or submit anything.

## Tagging a shipped build

After App Store Connect has the uploaded build, tag the shipped commit:

```sh
bundle exec fastlane ios tag_release version:2.0.0 build_number:100123
```

The tag lane:

- requires a clean Git working tree
- tags the current commit as `v<version>+<build_number>`
- accepts `version:2.0` and normalizes it to `2.0.0`
- requires `build_number:` to be passed explicitly
- refuses to overwrite an existing local or remote tag
- pushes only that tag to `origin`

Use the build number printed by `ios release`, not the checked-in
`CURRENT_PROJECT_VERSION` floor.

## Starting a maintenance branch

Only when a fix has to ship for a version that `main` has moved past. Branch
from that version's last tag, so the branch starts at exactly what shipped:

```sh
git fetch --tags
git checkout -b release/2.0 'v2.0.0+100008'
git push -u origin release/2.0
```

Fixes reach it through pull requests, as they reach `main`, each validated with
`make validate` from `Vault/`. Release and tag from the branch as from `main`,
with the patch version: `version:2.0.1`.
