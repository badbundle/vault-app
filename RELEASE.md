# Release Playbook

iOS and the Mac ship together. Every release builds both from one commit, with
one version and one build number, and uploads both, even when one of them has
no changes, so the two never drift apart.

Tags are the permanent release record. Release branches are maintenance lines
for supported versions, not the historical archive.

## Branch model

- Ship from `main`: build the commit to release, upload it, then tag that same
  commit.
- Tag every shipped build, including the App Store build number, for example
  `v2.1.0+100123`. One tag covers the iOS and Mac builds, which share the
  number. The tags say which commit became which build, so nothing else needs
  to.
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

## Versions

`MARKETING_VERSION` in [`VaultApp/Version.xcconfig`](VaultApp/Version.xcconfig)
is the version of every target: the iOS app, its AutoFill extension and
widgets, and the Mac app, its AutoFill extension and widgets. The project's
configurations are based on that file, and no target sets a version of its
own.

- Change the version there, and only there, in the pull request that starts
  the next version, such as 2.2.
- Don't change it in a target's General tab in Xcode: that writes a setting
  into the target, and `make validate`'s **Versions** check fails on it. The
  check also fails if any of the six bundles the iOS and Mac builds make has
  another version, or if their build numbers differ.

## Build numbers

Build numbers are global across all versions, branches and both platforms.
They identify App Store artifacts, not a marketing-version sequence, and the
iOS and Mac builds of a release always share one.

- Fastlane queries App Store Connect at release time for the latest iOS upload
  and the latest Mac upload, and builds both with the build after whichever is
  higher.
- `CURRENT_PROJECT_VERSION` in `VaultApp/Version.xcconfig` is a floor, not a
  record of the last build. A floor above the next build is used as it is, so
  raising it skips ahead to that number and never past it.
- Do not commit build-number bumps, before a release or after one. The lane
  passes the number to `xcodebuild`, so a bump never reaches the binary, and
  the tag already records it. A build made locally shows the floor, which is
  fine.
- It is fine for `release/2.1` to ship a build number higher than a later
  marketing version if that is the next global App Store build number.

To inspect the next build number, for both platforms, without changing
project files:

```sh
bundle exec fastlane increment_build
```

## Checking a build on a device

The unit tests stand in for Face ID and the passcode, and the simulator has
neither, so the app's use of the real ones is checked by hand, on an iPhone
with Face ID and a passcode, before each release. The Mac's checks follow, and
both are done for every release, as both platforms ship. With App Lock on and an App
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

The Mac app's use of the real Touch ID, screen capture, AutoFill and widgets is
checked by hand, on a Mac with Touch ID, before each release, and on each new
version of macOS.

**Capture.** With Hide While Recording on, take a screenshot (⇧⌘3), a screen
recording (⇧⌘5), a screen share (FaceTime or another app) and an AirPlay
mirror, each with these on screen in turn: the main window with a code's page,
an editor sheet, an alert, Settings, the QR code scanner and the AutoFill
sheet. None of them is in any capture. Turn Hide While Recording off: they all
are.

**Locking.**

- Lock Vault (⌃⌘L), go to another app and come back: Touch ID is asked for
  once, then the App Lock Password, and Vault unlocks. Do it again with the
  Mac's password instead of Touch ID.
- With Require Unlock at Immediately, open a locked item and unlock it with
  Touch ID: the item opens, and Vault stays unlocked.
- Lock Vault, and go to another app while Touch ID is being asked for: when
  you're back, Vault is still locked.
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

**Widgets.** Add Vault's widget to the desktop, and set it up with a code:

- Its settings list no codes while Vault is locked, and only codes a widget may
  show (not locked or hidden ones, and no counter-based ones) while it's
  unlocked.
- With Vault unlocked, the widget shows the code the app shows, and it changes
  with each period. Click the code: it's on the clipboard, and gone after the
  Clear Clipboard time, or as soon as Vault locks.
- Lock Vault (⌃⌘L), quit it, and lock the Mac, in turn: each time, the widget
  shows Vault locked straight away, or within five minutes at most.
- With Require Unlock at 5 Minutes, go to another app: the widget shows codes
  until Vault locks, then shows it locked.
- Click the widget anywhere but its code: Vault opens.

## Signing

The release lanes sign both platforms for the App Store with these, from the
developer account of team `442P244AFS`. They fetch each from the account before
they build, so the Mac that releases needs only the certificates' private keys
in its login keychain.

- **Apple Distribution certificate** (`PQ7Z28BJ65`, until 25 September 2027):
  signs the apps and extensions on both platforms. Its private key is in the
  login keychain of the Mac that releases.
- **Mac Installer Distribution certificate** (`QD3WB8NZZ8`, "3rd Party Mac
  Developer Installer: Bad Bundle Limited (442P244AFS)", made on 12 October
  2026, until 12 October 2027): signs the Mac's `.pkg`. Its private key is in
  the same keychain.
- **iOS App Store profiles**, one for each of `com.badbundle.vault`,
  `com.badbundle.vault.VaultAutofill` and `com.badbundle.vault.Widgets`, which
  `get_provisioning_profile` finds or makes.
- **Mac App Store profiles**, "Vault Mac App Store", "Vault Mac AutoFill App
  Store" and "Vault Mac Widgets App Store", for the same three bundle IDs and
  the Apple Distribution certificate, made on 12 October 2026. They grant the
  team's App Groups and keychain access groups (`442P244AFS.*`), which cover
  the Mac's App Group and its private, shared and widgets keychain groups (see
  Signing in [`docs/mac-app.md`](docs/mac-app.md#signing)). The lanes find them
  by name. Once one expires, sigh makes a new one, named after it with a
  timestamp, for the lanes to find instead.

A new Apple Distribution certificate needs new profiles on both platforms:
`get_certificates` and `get_provisioning_profile` make them on the next
release, as they made the Mac's.

## Shipping a build

Run the release lane only when you intend to build and upload real App Store
builds for both platforms:

```sh
bundle exec fastlane release
```

The release lane:

- requires a clean Git working tree
- works out the next build number, for iOS and the Mac, as above
- archives and exports the iOS app (`VaultApp.ipa`) and the Mac app
  (`Vault.pkg`), each with `CURRENT_PROJECT_VERSION=<that build number>`
- checks every bundle it exported, on both platforms, before it uploads either:
  each has the version in `VaultApp/Version.xcconfig` and that build number, is
  signed with the Apple Distribution certificate, has no `get-task-allow` and
  no temporary exceptions, and has exactly the App Groups and keychain access
  groups its target's entitlements list. On the Mac, each is also sandboxed,
  with the hardened runtime, and the `.pkg` is signed with the Mac installer
  certificate. A build that fails any of them uploads nothing
- uploads the iOS build to App Store Connect, with the listing in
  `fastlane/metadata/` and the screenshots in `fastlane/screenshots/en-US/`
- uploads the Mac build, with the Mac's listing in `fastlane/metadata-mac/`
  and its screenshots in `fastlane/screenshots-mac/en-US/`
- makes each platform's version in App Store Connect the version being built:
  it renames the version App Store Connect is editing, or adds one if it isn't
  editing any. The screenshots replace the version's, so one that changed, was
  renamed or was removed doesn't stay behind
- sets both versions to be released by hand once they're approved
- does not attach the builds to the versions, submit anything, commit
  build-number changes, or create or push Git tags

Building both takes about 3 minutes on the Mac Studio, and the uploads a few
more.

Every build tells App Store Connect that Vault uses no encryption needing export
compliance documentation (`ITSAppUsesNonExemptEncryption` is `NO`, on iOS and
the Mac), so there's no export question to answer. That holds only while all
of Vault's encryption is Apple's CryptoKit:
[`docs/export-compliance.md`](docs/export-compliance.md) says why, and what to
do if that changes.

Record the build number printed by the release lane, for example:

```text
Using release build number 100123 for 2.1 on iOS and the Mac
```

To build, sign and check both platforms as the release lane does, without
uploading anything, for example after a change to signing:

```sh
bundle exec fastlane build_release
```

It takes `build_number:` to build with a number of your own, rather than the
next one.

If a build succeeded but its upload failed, retry the existing file's upload.
The listing and screenshots go up before the binary, so they're already there:

```sh
bundle exec fastlane ios upload
bundle exec fastlane mac upload
```

The upload lanes do not build, bump, commit, or tag anything.

## Attaching the builds

Once both builds have uploaded, attach each to its platform's version:

```sh
bundle exec fastlane attach_builds build_number:100123
```

It waits for App Store Connect to finish processing each build, which takes a
few minutes, then selects it for the iOS or macOS version App Store Connect is
editing, which must be the version being built. It doesn't submit anything.

## Submitting for review

With both builds attached, both versions have everything App Review needs.
Before submitting:

- [Check the build on an iPhone](#checking-a-build-on-a-device) and
  [on a Mac](#checking-a-build-on-a-mac), from TestFlight.
- Read each version's listing, screenshots and What's New in App Store Connect.

Then submit the iOS and macOS versions for review in App Store Connect. Both
are released by hand: release them together once both are approved, so the
App Store never has one platform ahead of the other.

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

The Mac app's screenshots are in `fastlane/screenshots-mac/en-US/`, apart from
the iOS ones, as deliver would send every image in a folder to one platform's
version. To replace the Mac app's version's screenshots with them:

```sh
bundle exec fastlane mac upload_screenshots
```

It needs a macOS version that App Store Connect is editing, and does no more
than the iOS lane. The release lane uploads both.

## Updating the creative assets

The product page header and the search results image (see
[Creative assets](Vault/Screenshots/README.md#creative-assets)) are in
`fastlane/creative-assets/` (`header.png` and `search-results.png`). Neither
fastlane nor spaceship can upload them yet, so they go up by hand in App Store
Connect: in the iOS version's Product Page Information, under Header and
Search Results, before it's submitted, or on their own as an Asset Library
submission, which is reviewed against the latest version. They show on iOS 27
and iPadOS 27 or later.

## Updating the listing

Each platform's version in App Store Connect has its own listing text, so each
has its own folder:

- `fastlane/metadata/` is the iOS listing, and the app's own details, which
  both platforms share: the name and subtitle (which, with the keywords, are
  the only fields App Store search reads), the privacy policy's URL, the
  categories and the copyright. Its `en-US/` has the description, keywords,
  promotional text, What's New (`release_notes.txt`) and URLs, and
  `review_information/` the notes for App Review. The App Privacy answers,
  which are the app's, are in `fastlane/app_privacy_details.json`.
- `fastlane/metadata-mac/` is the Mac listing: only the version's own text,
  so it never sets the shared details. Where its text is the same as iOS's,
  its file is a link to iOS's (the keywords, promotional text, URLs and
  copyright). The description, What's New and review notes are its own, and
  make no claim that's only true on an iPhone: check each against
  [`docs/mac-app.md`](docs/mac-app.md) and
  [`docs/security-model.md`](docs/security-model.md). The review notes say
  that the App Lock Password is required on the Mac.

Every release updates What's New in both, from `CHANGELOG.md`. App Store
Connect takes no What's New for a platform's first version, so deliver skipped
the Mac's for 2.1, and again for 2.2: App Review rejected the Mac's 2.1, which
was never released, so the release lane renamed that version 2.2 and it's still
the Mac's first.

The release lane uploads both listings with every build. To upload them
without a build:

```sh
bundle exec fastlane ios upload_metadata
bundle exec fastlane mac upload_metadata
```

Each changes the version App Store Connect is editing on its platform. The
iOS lane also publishes the privacy answers. Neither builds, uploads a binary
or screenshots, or submits anything.

## Tagging a shipped build

After App Store Connect has both uploaded builds, tag the shipped commit:

```sh
bundle exec fastlane tag_release build_number:100123
```

The tag lane:

- requires a clean Git working tree
- tags the current commit as `v<version>+<build_number>`, one tag for both
  platforms
- takes the version from `VaultApp/Version.xcconfig`, or `version:`, and
  normalizes `2.1` to `2.1.0`
- requires `build_number:` to be passed explicitly
- refuses to overwrite an existing local or remote tag
- pushes only that tag to `origin`

Use the build number printed by `release`, not the checked-in
`CURRENT_PROJECT_VERSION` floor.

## Starting a maintenance branch

Only when a fix has to ship for a version that `main` has moved past. Branch
from that version's last tag, so the branch starts at exactly what shipped:

```sh
git fetch --tags
git checkout -b release/2.1 'v2.1.0+100123'
git push -u origin release/2.1
```

Fixes reach it through pull requests, as they reach `main`, each validated with
`make validate` from `Vault/`. The first sets the patch version in
`VaultApp/Version.xcconfig`, such as 2.1.1. Release and tag from the branch as
from `main`, for both platforms.
