# Marketing Screenshots

App Store screenshots are generated, not hand-made: the app is captured on
fresh simulators, and the Mac app on this Mac, in a fixed demo state, then
each capture is put in a device frame, or shown as a Mac window, with a title
and subtitle by
[device-screenshot-framer](https://github.com/badbundle/device-screenshot-framer),
a Swift package dependency of `Vault` (its `framer` executable is run through
`swift run`).

```sh
make screenshots           # capture + frame: iPhone, iPad and Mac
make screenshots-capture   # raw captures only
make screenshots-frame     # frame existing captures only (fast; iterate on copy here)
```

Run from `Vault/`. Framed output lands in `fastlane/screenshots/en-US/`,
which is where `upload_to_app_store` looks, and the Mac's in
`fastlane/screenshots-mac/en-US/` (see [Mac](#mac)). The next `fastlane ios release`
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
3. For `mac` it builds `VaultMacApp` (Debug) into the same derived data and
   launches it once per scene and appearance on this Mac (see [Mac](#mac)).
   Captures go to `.build/screenshots/raw/mac/NN-<scene>[-dark].png`.
4. `framer render` reads `iphone.json`, `ipad.json` and `mac.json` and writes
   the framed images.

`capture.sh iphone`, `capture.sh mac` and so on capture only those classes.

The launch argument is handled by `Sources/VaultiOS/Mocks/ScreenshotMode.swift`
(debug builds only). It swaps in an empty in-memory vault so the simulator's
real vault is never shown or touched, seeds the demo items and tags defined
there, and opens the requested scene. Add a scene there and to `SCENES` in
`capture.sh` to capture a new screen.

The demo vault itself, shared with the Mac app, is `DemoVault` in VaultFeed:
recovery phrases and private keys first, then notes and codes. Its phrases and
keys were generated for the screenshots, with valid checksums (`DemoVaultTests`
checks them), and were never funded; its SSH key is made afresh at each launch.
As in the app, each one is an encrypted item with a password of its own, and
locked: every encrypted demo item's password is `hello`
(`DemoVault.encryptedItemPassword`). It also moves the app's clock (`DemoVault.clockOffset`) so every demo
code is 3 seconds into its 30-second period as the app launches. After the
capture's wait the countdown bars show about 70% left in every shot, never a
nearly empty bar, and the codes are still the right ones for the clock's time.
Raising `SCREENSHOT_SETTLE_SECONDS` lowers the bars.

## Scenes

| Scene               | Shows |
| ------------------- | ----- |
| `feed`              | The feed of the demo vault, recovery phrases and private keys first. |
| `detail`            | The first item's page, the "Cold storage" recovery phrase, with its words masked. |
| `search`            | The feed searching for `blue heron`, the passphrase of the three hidden items, which are never in the feed: the "Savings wallet" recovery phrase, a code and a note. |
| `editor`            | The first code's editor (GitHub) on Privacy & Security, part way through hiding it behind `blue heron`, locking it and giving it the killphrase `paper lantern`. Nothing is saved. On iPad the sheet is scrolled to its end, so the killphrase shows. |
| `lock`              | The lock screen, asking for the App Lock Password. |
| `app-lock-password` | Settings with the App Lock Password's sheet open: Set Duress Password, and Erase Vault After 10 Failed Passwords on. |
| `backups`           | The Backups page, with a backup and a backup password. |
| `settings`          | Settings, with App Lock and the App Lock Password on. |
| `phrase-editor`     | The "Everyday wallet" recovery phrase's editor on its words: its 12 words masked, and its checksum valid. Nothing is saved. On iPad the sheet is scrolled to its end, so the checksum shows. |
| `code-detail`       | The first code's page (GitHub), with its code and countdown. |

New scenes go on the end of `SCENES`, as the configs name the captures by
their numbers.

The `detail` and `phrase-editor` scenes open a recovery phrase as someone
would once they'd entered its password and Face ID had passed: screenshot mode
hands the item's page the phrase it decrypted as it seeded the vault, and opens
it unlocked, with its words still masked. A recovery phrase or private key
hides while Vault isn't the active app or the screen is captured (G41, G103),
but `simctl io screenshot` reads the simulator's display without iOS counting
the screen as captured, and the app is in front, so nothing is hidden for the
capture: screenshot mode changes nothing about the hiding.

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
| mac    | this Mac, at 2x        | main window 2240×1400, Settings 1080×1632 | Mac, 2880×1800 |

Override with `SCREENSHOT_IPHONE_DEVICE`, `SCREENSHOT_IPAD_DEVICE` and
`SCREENSHOT_RUNTIME`. Each capture waits `SCREENSHOT_SETTLE_SECONDS`
(default 5) after launch, and 4 seconds more for the scenes that get past the
lock. If shots come out blank, with masked codes, or with the vault door
where a screen should be, the app hadn't finished launching: don't run builds
or tests alongside the capture, or raise the wait. The framer detects the
frame from the pixel size, so a different simulator needs a matching `device`
in the config (`swift run -c release framer list-devices`).

## Mac

The Mac app has its own screenshot mode,
`Sources/VaultMac/Mocks/VaultMacScreenshotMode.swift` (debug builds only),
on the same `DemoVault`. `-screenshot-scene <scene>` runs the app on the demo
vault in memory, with defaults, keychain items, widget codes and a storage
directory of its own, so the Mac's own vault, keychain and widgets are never
read or written. Touch ID passes, the App Lock Password is a stand-in that's
set, and the lock triggers are off, so the scene stays open whichever app is
in front. The main window is 1120×700 points, 16:10.

| Scene      | Shows |
| ---------- | ----- |
| `feed`     | The list of items, none open. |
| `detail`   | The first item's page, the "Cold storage" recovery phrase, with its words masked. |
| `editor`   | The first code's editor sheet (GitHub), scrolled to Privacy & Security: locked, hidden behind `blue heron`, with the killphrase `paper lantern`. Nothing is saved. |
| `lock`     | The lock screen, asking for the App Lock Password. |
| `backups`  | Backups, on the backup password's page. |
| `settings` | The Settings window's Security tab, with the App Lock Password and erasing after failed passwords on. |
| `phrase-editor` | The "Everyday wallet" recovery phrase's editor sheet: its words in secure fields, and its checksum valid. Nothing is saved. |
| `code-detail` | The first code's page (GitHub), with its code and countdown. |

In `detail` and `phrase-editor`, screenshot mode enters the encrypted item's
password (`hello`) on its page, and Touch ID passes for it. A recovery
phrase's page locks again whenever Vault stops being the active app (G88), as
it may while the scene settles behind the terminal, so in screenshot mode the
page unlocks itself again once Vault is back in front, as it is for the
capture; the words stay masked throughout.

Every Vault window is kept out of screen captures (Hide While Recording,
`sharingType` `.none`), and capturing the screen would need the screen
recording permission, so `capture.sh` doesn't capture the screen. The app
captures its own window: once the scene has settled it comes to the front,
asks ScreenCaptureKit for its own window (`SCShareableContent.currentProcess`,
which needs no permission), and writes it as a PNG to a file descriptor that
`capture.sh` opens for it (`-screenshot-fd 3`), then quits. For that, screenshot
mode alone sets its windows' `sharingType` to `.readOnly`; nothing else about
their privacy changes, and a release build has no screenshot mode. Drawing the
window in the app instead (`cacheDisplay`) leaves out everything on Liquid
Glass or drawn with vibrancy, such as the sidebar.

macOS draws a window at its display's scale, so the capture needs the window
on a Retina display, and the Mac unlocked: on a display at 1x the app says so
and `capture.sh` stops. Each launch takes the front for about 5 seconds, so
the window is drawn active, with the list's selection in the accent colour;
if it can't get the front, it captures nothing and `capture.sh` stops. Leave
the Mac alone while it runs. `capture.sh` passes
`-ApplePersistenceIgnoreState YES`, as the Mac UI tests do: launched from a
terminal, an app that was stopped before it quit otherwise opens no window
at all, and `-AppleShowScrollBars WhenScrolling`, so the lists have no scroll
bars.

The Mac App Store takes 1280×800, 1440×900, 2560×1600 or 2880×1800. `mac.json`
renders 2880×1800, with each capture as a frameless window (`"frame":
"window"`) with rounded corners and the drop shadow, in the iOS set's style.
deliver sends every image in a folder to the one platform's version, telling
devices apart only by size, so the Mac set is kept in
`fastlane/screenshots-mac/en-US/`, out of the iOS lanes' folder, and
`bundle exec fastlane mac upload_screenshots` replaces the Mac app's
screenshots with exactly those, as the iOS lane does.

## Layouts and copy

Titles, subtitles, frame colours, the background, and where each device and
callout sits live in `iphone.json`, `ipad.json` and `mac.json`; the
[config reference](https://github.com/badbundle/device-screenshot-framer#config-file-reference)
documents every key, including the
[layouts](https://github.com/badbundle/device-screenshot-framer#layouts).
Every image shares one background, in the icon's colours: near-black,
deepening to navy at the bottom, lit by soft glows of Vault's blue behind the
devices, with the icon's vault door, very faint and oversized, behind the
title (`assets/vault-door.png`, the dark icon's glyph rendered at 3072 pixels
by `swift run vault-app-icon-generator -o <dir> --size 3072` and trimmed). A
panorama has its own `background`, with a glow and a door per page. Every
title is the same size and sits the same distance from the top
(`"anchor": "edge"`, `minScale` and `maxScale` 1), with one word in the
accent blue (`accent`), and the devices start just below the text, large and
tilted, running off the bottom. Devices cast a shadow and have a Silver frame,
apart from the dark screens, which get Deep Blue (iPhone) or Space Gray (iPad)
to set them apart from the light ones.

Where a page has a focal point, a callout lifts it off the screen on a blue
glow, with no border. A card is left over the part it lifts (no `x` / `y`,
the device's rotation) and sized so its edges land in the gaps around it, so
nothing shows half-covered at its edges; `offsetX` / `offsetY`, in the
capture's pixels, nudge it to fit those gaps. The exception is the search
field, which is moved up into the empty space below the search results.

Each device class tells the same story in ten images, Apple's limit, the
strongest first. The first three show in search results, so they sell Vault
on their own: what it keeps, then what it does when someone makes you open it.

1. **Your keys. Offline.** The "Cold storage" recovery phrase's page, with
   its checksum and masked words lifted out.
2. A panorama of three, one canvas cut into `-1`, `-2` and `-3`, about being
   made to unlock Vault:
   - **Forced to unlock it?:** the App Lock Password's settings, with Set
     Duress Password lifted out;
   - **One search deletes it:** the editor's Privacy & Security step, with
     the killphrase lifted out;
   - **Erase after 10 wrong tries:** the same settings as the first page, in
     dark, with the erase row lifted out.
3. **Checked as you type:** the phrase editor on its words, with "Valid
   BIP39 phrase" lifted out.
4. **Locked with a password:** the dark lock screen, with its door and "Vault
   Locked" lifted out and most of the keyboard cropped off.
5. **Hidden until you search:** the search for `blue heron` finding the
   hidden "Savings wallet", with its search field lifted up under the results
   (on iPhone, in front of the feed that doesn't show them).
6. **Backups you can hold:** the Backups page, with its last backup ("Exported
   to PDF") lifted out.
7. **2FA codes too:** a code's page, with its code and countdown lifted out.
8. **Private by design:** Settings in light and dark, overlapping.

The Mac tells the same story in five, in the same order, each a window (or
two) on the same background:

1. **Your keys. Offline.** The "Cold storage" recovery phrase open beside the
   list, with its masked words lifted out.
2. **Forced to unlock it?:** the dark lock screen, with the Settings window's
   Security tab over it and Set Duress Password lifted out.
3. **One search deletes it:** the editor sheet, with the killphrase lifted out.
4. **Backups you can hold:** Backups, with the last backup ("Exported to
   PDF") lifted out.
5. **Private by design:** the list, with Settings in dark over it and Hide
   While Recording lifted out.

`deliver` orders each device's screenshots by file name (naturally sorted),
so the numbers in the names are the order on the App Store.

The copy is short and says only what holds, as the in-app help and
[`docs/security-model.md`](../../docs/security-model.md) put it, limits
included: phrases and keys are always encrypted (G41, G102), the phrase
editor checks each word against the BIP39, SLIP-39, Electrum or Monero word
list as it's typed, a killphrase deletes the item "from this vault" (backups
made before still have it), erasing happens "if you turn it on" after 10
wrong App Lock Passwords in a row (the title's "tries"), and the clipboard
clears after a minute "by default" (G50). Check a new claim against both before
using it. Newlines in a title or subtitle start a new line; the subtitles
are broken by hand so their lines balance. Apple rejects iPad screenshots
that show an iPhone, so the iPad config only ever places iPads.

## Creative assets

Since iOS 27 and iPadOS 27, the App Store can show two more images for an
iOS app: a **product page header** (21:9, 3840×1646, above the icon and name)
and a **search results** image (3:2, 1920×1280 up to 3840×2560). Neither is
offered for macOS. `creative-header.json` and `creative-search.json` make
them in the screenshots' style from the same raw captures, as `header.png`
(3840×1646) and `search-results.png` (3840×2560) in
`fastlane/creative-assets/`, which neither deliver lane reads:

```sh
swift run -c release framer render --config Screenshots/creative-header.json
swift run -c release framer render --config Screenshots/creative-search.json
```

Both are bigger than any capture, which the framer allows only with
`"clamp": false` in `output`, and Apple takes no alpha or transparency in
either, so they're written with `"opaque": true`: a PNG without an alpha
channel.

- **Header:** one brand-led idea, "Your keys. Your secrets.", over the iPad
  feed, recovery phrases and private keys first, between a recovery phrase's
  page and the lock screen on iPhone. The title and the iPad are in the
  middle, so they still read when the image is cropped; the app's icon and
  name sit below it.
- **Search results:** states the obvious with the real interface: "No
  accounts. No tracking." and "Seed phrases, private keys and notes, fully
  offline." over the dark iPad feed and a recovery phrase's page on iPhone.
  Check it at about 600 pixels wide, the size of a search result.

Apple's rules for them: short text, the focal point in the middle, and no
claim we can't back (no prices, URLs, ©, awards or other platforms' logos).
The copy here is the screenshots' copy, so the same checks apply.

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
the titles should read easily there, the text shouldn't touch a device (the
titles never shrink, so nothing else stops it), nothing should show
half-covered at a callout's edges, and the codes shouldn't be masked.

Frames are downloaded on first use into
`~/Library/Caches/device-screenshot-framer/`.
