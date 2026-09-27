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
- uploads the build to App Store Connect
- does not commit build-number changes
- does not create or push Git tags

Record the build number printed by the release lane, for example:

```text
Using release build number 100123
```

If the build succeeded but upload failed, retry the existing IPA upload:

```sh
bundle exec fastlane ios upload
```

The upload lane does not build, bump, commit, or tag anything.

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
