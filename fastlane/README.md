fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### increment_build

```sh
[bundle exec] fastlane increment_build
```

Prints the next build number for iOS and the Mac, without changing project files

### release

```sh
[bundle exec] fastlane release
```

Archive, sign, check and upload iOS and the Mac, with one build number, their listings and screenshots. Submits nothing

### attach_builds

```sh
[bundle exec] fastlane attach_builds
```

Attach the builds uploaded with build_number: to the iOS and macOS versions App Store Connect is editing. Submits nothing

### build_release

```sh
[bundle exec] fastlane build_release
```

Archive, sign and check iOS and the Mac with the next build number, or build_number:, without uploading

### tag_release

```sh
[bundle exec] fastlane tag_release
```

Tag and push the current commit as the iOS and Mac builds uploaded with build_number:

----


## iOS

### ios upload

```sh
[bundle exec] fastlane ios upload
```

Upload the existing VaultApp.ipa to App Store Connect (no build, no bump, no listing)

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Replace the App Store screenshots with fastlane/screenshots (no build, no listing)

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload the App Store listing's text, review notes and privacy answers (no build, no screenshots)

----


## Mac

### mac upload

```sh
[bundle exec] fastlane mac upload
```

Upload the existing Vault.pkg to App Store Connect (no build, no bump, no listing)

### mac upload_screenshots

```sh
[bundle exec] fastlane mac upload_screenshots
```

Replace the Mac App Store screenshots with fastlane/screenshots-mac (no build, no listing)

### mac upload_metadata

```sh
[bundle exec] fastlane mac upload_metadata
```

Upload the Mac App Store listing's text and review notes from fastlane/metadata-mac (no build, no screenshots)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
