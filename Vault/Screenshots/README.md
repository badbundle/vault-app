# Marketing Screenshots

App Store screenshots are generated, not hand-made: the app is captured on
fresh simulators in a fixed demo state, then each capture is put in a device
frame with a title and subtitle by
[device-screenshot-framer](https://github.com/badbundle/device-screenshot-framer),
a Swift package dependency of `Vault` (its `framer` executable is run through
`swift run`).

```sh
make screenshots           # capture + frame, both device classes
make screenshots-capture   # raw captures only
make screenshots-frame     # frame existing captures only (fast; iterate on copy here)
```

Run from `Vault/`. Framed output lands in `fastlane/screenshots/en-US/`,
which is where `upload_to_app_store` looks. The next `fastlane ios release`
uploads whatever is there, or `bundle exec fastlane ios upload_screenshots`
uploads only the screenshots, without a build (see
[`RELEASE.md`](../../RELEASE.md#updating-the-screenshots)). Either replaces
the version's screenshots with exactly the files in that folder, so when an
image is renamed or dropped, delete its old file too.

## Pipeline

1. `capture.sh` builds `VaultApp` (Debug, simulator) into
   `.build/screenshots/DerivedData`.
2. For each device class it creates a throwaway simulator
   (`vault-screenshots-iphone` / `-ipad`), sets the 9:41 marketing status
   bar, installs the app and launches it once per scene with
   `-screenshot-scene <scene>`, in light and then dark appearance. Captures go
   to `.build/screenshots/raw/<class>/NN-<scene>[-dark].png`. The simulators
   are deleted afterwards (`SCREENSHOT_KEEP_SIMULATORS=1` keeps them).
3. `framer render` reads `iphone.json` / `ipad.json` and writes the framed
   images.

The launch argument is handled by `Sources/VaultiOS/Mocks/ScreenshotMode.swift`
(debug builds only). It swaps in an empty in-memory vault so the simulator's
real vault is never shown or touched, seeds the demo items and tags defined
there, and opens the requested scene. Add a scene there and to `SCENES` in
`capture.sh` to capture a new screen.

## Scenes

| Scene               | Shows |
| ------------------- | ----- |
| `feed`              | The feed of the demo vault. |
| `detail`            | The first item's page (GitHub), with its code and countdown. |
| `search`            | The feed searching for `blue heron`, the passphrase of the four hidden items, which are never in the feed. |
| `editor`            | The first item's editor on Privacy & Security, part way through hiding it behind `blue heron`, locking it and giving it the killphrase `paper lantern`. Nothing is saved. On iPad the sheet is scrolled to its end, so the killphrase shows. |
| `lock`              | The lock screen, asking for the App Lock Password. |
| `app-lock-password` | Settings with the App Lock Password's sheet open: Set Duress Password, and Erase Vault After 10 Failed Passwords on. |
| `backups`           | The Backups page, with a backup and a backup password. |
| `settings`          | Settings, with App Lock and the App Lock Password on. |

In every scene Face ID passes, as on a device with a passcode, so no screen
says to set one up. The App Lock Password and the backup password are
stand-ins that say they're set: the demo vault stays in memory, unencrypted,
and the keychain's backup password is never read. `lock`,
`app-lock-password` and `settings` start locked with the App Lock Password
set, and the last two enter it (`correct horse battery`) to get past the
lock, as someone would. The simulator's keyboard shows on the lock screen;
the layouts crop most of it off.

## Devices

| Class  | Simulator              | Pixels    | App Store slot |
| ------ | ---------------------- | --------- | -------------- |
| iphone | iPhone 18 Pro Max      | 1320×2868 | iPhone 6.9"    |
| ipad   | iPad Pro 13-inch (M5)  | 2064×2752 | iPad 13"       |

Override with `SCREENSHOT_IPHONE_DEVICE`, `SCREENSHOT_IPAD_DEVICE` and
`SCREENSHOT_RUNTIME`. Each capture waits `SCREENSHOT_SETTLE_SECONDS`
(default 5) after launch, and 4 seconds more for the scenes that get past the
lock. If shots come out blank, with masked codes, or with the vault door
where a screen should be, the app hadn't finished launching: don't run builds
or tests alongside the capture, or raise the wait. The framer detects the
frame from the pixel size, so a different simulator needs a matching `device`
in the config (`swift run -c release framer list-devices`).

## Layouts and copy

Titles, subtitles, frame colours, the background, and where each device and
callout sits live in `iphone.json` and `ipad.json`; the
[config reference](https://github.com/badbundle/device-screenshot-framer#config-file-reference)
documents every key, including the
[layouts](https://github.com/badbundle/device-screenshot-framer#layouts).
Every image shares one background: near-black at the top, where the text
sits, lightening to Vault's blue at the bottom. Devices cast a shadow and
have a Silver frame, apart from the dark settings screens, which get Deep
Blue (iPhone) or Space Gray (iPad) to set them apart from the light ones.

Each device class tells the same story in nine images, the strongest first:

1. **Every code. Every secret.** The feed, as one large tilted device running
   off the bottom.
2. A panorama of three, one canvas cut into `-1`, `-2` and `-3`, about being
   made to unlock Vault:
   - **Locked with a password:** the dark lock screen, asking for the App Lock
     Password (on iPad, with its door enlarged into a card);
   - **Forced to unlock it?:** the App Lock Password's settings, with Set
     Duress Password enlarged;
   - **Erase after 10 wrong passwords:** the same settings in dark, with the
     erase row enlarged.
3. **Hidden until you search:** the search for `blue heron` finding the
   hidden items, with its search field enlarged (on iPhone, in front of the
   feed that doesn't show them; on iPad, with the hidden items enlarged too).
4. **One search deletes it:** the editor's Privacy & Security step, with the
   killphrase enlarged.
5. **Tap to copy:** an item's page, with its code and countdown enlarged.
6. **Backups you can hold:** the Backups page, barely tilted, running off the
   bottom.
7. **Private by design:** Settings in light and dark, overlapping.

The copy is short and says only what holds, as the in-app help and
[`docs/security-model.md`](../../docs/security-model.md) put it, limits
included: a killphrase deletes the item "from this vault" (backups made
before still have it), erasing happens "if you turn it on", and the clipboard
clears after a minute "by default". Check a new claim against both before
using it. Newlines in a title or subtitle start a new line; the subtitles
are broken by hand so their lines balance. Apple rejects iPad screenshots
that show an iPhone, so the iPad config only ever places iPads.

## Iterating

Edit a config, then re-run `make screenshots-frame`: no rebuild or capture
needed. To try a change without touching `fastlane/`, render somewhere else:

```sh
swift run -c release framer render --config Screenshots/iphone.json -o /tmp/framed
```

A callout's `region` is in the raw capture's pixels, so it has to move if the
screen it points at is laid out differently: crop the raw capture to find
it (`magick 06-app-lock-password.png -crop 1200x176+60+1636 out.png`). The
text fits itself to the devices, so moving a device moves and resizes its
text too.

Check each image at full size and at the size the App Store shows it in
search results, about 300 pixels wide (`magick in.png -resize 300x out.png`):
the titles should read easily there, the text shouldn't touch a device, and
the codes shouldn't be masked.

Frames are downloaded on first use into
`~/Library/Caches/device-screenshot-framer/`.
