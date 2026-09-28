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

Prints the next global App Store/TestFlight build number without changing project files

----


## iOS

### ios release

```sh
[bundle exec] fastlane ios release
```

Push a new release build to the App Store

### ios upload

```sh
[bundle exec] fastlane ios upload
```

Upload the existing VaultApp.ipa to App Store Connect (no build, no bump)

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Replace the App Store screenshots with fastlane/screenshots (no build, no listing)

### ios tag_release

```sh
[bundle exec] fastlane ios tag_release
```

Tag and push the current commit for an uploaded App Store build

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
