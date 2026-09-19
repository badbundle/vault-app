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
which is where `upload_to_app_store` looks, so the next `fastlane ios release`
uploads whatever is there.

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

## Devices

| Class  | Simulator              | Pixels    | App Store slot |
| ------ | ---------------------- | --------- | -------------- |
| iphone | iPhone 18 Pro Max      | 1320×2868 | iPhone 6.9"    |
| ipad   | iPad Pro 13-inch (M5)  | 2064×2752 | iPad 13"       |

Override with `SCREENSHOT_IPHONE_DEVICE`, `SCREENSHOT_IPAD_DEVICE` and
`SCREENSHOT_RUNTIME`. Each capture waits `SCREENSHOT_SETTLE_SECONDS`
(default 5) after launch; if shots come out blank or with masked codes the app
hadn't finished launching — don't run builds or tests alongside the capture,
or raise the wait. The framer detects the frame from the pixel size, so a
different simulator needs a matching `device` in the config
(`swift run -c release framer list-devices`).

## Copy and styling

Titles, subtitles, frame colour, background gradient and text styling live in
`iphone.json` and `ipad.json`; the
[config reference](https://github.com/badbundle/device-screenshot-framer#config-file-reference)
documents every key. Newlines in a title start a new line. Re-run
`make screenshots-frame` after editing — no rebuild or capture needed.

Frames are downloaded on first use into
`~/Library/Caches/device-screenshot-framer/`.
